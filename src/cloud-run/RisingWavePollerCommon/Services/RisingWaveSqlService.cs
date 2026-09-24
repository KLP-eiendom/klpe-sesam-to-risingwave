namespace RisingWavePollerCommon.Services
{
    using System.Text;
    using RisingWavePollerCommon.Models;
    using RisingWavePollerCommon.Settings;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using Npgsql;

    public interface IRisingWaveTableConfig
    {
        string ResolvedTargetTable { get; }

        IReadOnlyList<string> EffectivePrimaryKeyColumns { get; }

        /// <summary>
        /// When true, <see cref="IRisingWaveService{T}.ReconcileAsync"/> will be called after each
        /// successful poll to delete rows whose primary key no longer appears in the source system.
        /// Only enable for entities where the full dataset is always fetched (no WhereClause filter).
        /// </summary>
        bool EnableReconciliation => false;
    }

    public sealed class RisingWaveSqlService : IRisingWaveService<IRisingWaveTableConfig>
    {
        // Tables larger than this will not be reconciled — pass too large for the UNNEST approach.
        // Use a full-refresh (--full-refresh + re-poll) for such tables instead.
        private const int ReconciliationRowLimit = 100_000;

        private readonly ILogger<RisingWaveSqlService> logger;
        private readonly RisingWaveSettings settings;

        public RisingWaveSqlService(
            ILogger<RisingWaveSqlService> logger,
            IOptions<RisingWaveSettings> settings)
        {
            this.logger = logger;
            this.settings = settings.Value;

            this.logger.LogInformation(
                "RisingWave SQL configured: {Host}:{Port}/{Database}.{Schema} (default batch: {BatchSize})",
                this.settings.SqlHost,
                this.settings.SqlPort,
                this.settings.Database,
                this.settings.Schema,
                this.settings.BatchSize);
        }

        public async Task<PublishResult> PublishRowsAsync(
            IReadOnlyList<IReadOnlyDictionary<string, object>> rows,
            IRisingWaveTableConfig tableConfig,
            int batchSize,
            CancellationToken cancellationToken = default)
        {
            var result = new PublishResult();
            var targetTable = tableConfig.ResolvedTargetTable;

            if (rows.Count == 0)
            {
                this.logger.LogInformation("No rows to publish to {Table} — skipping", targetTable);
                return result;
            }

            var nullIdCount = rows.Count(r => !r.TryGetValue("_id", out var id) || id is null or "");
            if (nullIdCount > 0)
            {
                this.logger.LogWarning(
                    "Skipping {Count} row(s) with null/empty _id for {Table}",
                    nullIdCount,
                    targetTable);
                result.ErrorCount += nullIdCount;
                rows = rows.Where(r => r.TryGetValue("_id", out var id) && id is not null and not "").ToList();
                if (rows.Count == 0)
                {
                    return result;
                }
            }

            // Union of keys across ALL rows, not just rows[0] — JSON APIs commonly omit an
            // optional/null field per-entity rather than sending it as explicit null, so scoping
            // the column set to a single row can silently drop a column (and therefore every row's
            // value for it, not just the rows missing it) from the whole publish whenever the
            // entity that happens to be first in the batch lacks that field.
            var allColumns = rows.SelectMany(r => r.Keys).Distinct().ToArray();

            await using var conn = new NpgsqlConnection(this.settings.ConnectionString);
            await conn.OpenAsync(cancellationToken);

            // For auto-DDL inference (only reached when the table doesn't exist yet — dbt-managed
            // tables return early inside EnsureTableExistsAsync): use the first non-null value seen
            // for each column across all rows, since rows[0] may not have every column either.
            var sampleValues = allColumns
                .Select(col => (object)(rows.Select(r => r.TryGetValue(col, out var v) ? v : null).FirstOrDefault(v => v != null) ?? DBNull.Value))
                .ToArray();

            await this.EnsureTableExistsAsync(
                conn,
                this.settings.Schema,
                targetTable,
                allColumns,
                sampleValues,
                tableConfig.EffectivePrimaryKeyColumns,
                cancellationToken);

            // Filter to only columns defined in the table — the DDL is the source of truth.
            // Extra fields returned by the API (not in the schema) are silently dropped.
            // We use Case-Insensitive matching because dbt may create tables with lowercase names (unquoted).
            var tableColumnMap = await GetTableColumnsAsync(conn, this.settings.Schema, targetTable, cancellationToken);
            var mapping = new List<(string RowKey, string DbColumn, string DataType)>();
            foreach (var key in allColumns)
            {
                if (tableColumnMap.TryGetValue(key, out var info))
                {
                    mapping.Add((key, info.ActualName, info.DataType));
                }
            }

            var columns = mapping.Select(m => m.DbColumn).ToArray();

            if (columns.Length == 0)
            {
                this.logger.LogError(
                    "No columns from source match the schema of {Table} — schema mismatch. Skipping publish. Source columns: {Columns}",
                    targetTable,
                    string.Join(", ", allColumns));
                return result;
            }

            if (columns.Length < allColumns.Length)
            {
                var skipped = allColumns.Except(mapping.Select(m => m.RowKey)).ToArray();
                this.logger.LogDebug(
                    "Skipping {Count} column(s) not in {Table} schema: {Columns}",
                    skipped.Length,
                    targetTable,
                    string.Join(", ", skipped));
            }

            var columnList = "(" + string.Join(", ", columns.Select(c => $"\"{c}\"")) + ")";

            // Pre-build a reusable command for full batches — parameters are set (not re-added) each
            // iteration, avoiding repeated NpgsqlParameter allocation and SQL re-parsing on the server.
            NpgsqlCommand fullCmd = null;
            if (rows.Count >= batchSize)
            {
                var fullBatchSql = BuildInsertSql(this.settings.Schema, targetTable, columnList, batchSize, columns);
#pragma warning disable CA2100
                fullCmd = new NpgsqlCommand(fullBatchSql, conn);
#pragma warning restore CA2100
                for (var i = 0; i < batchSize * columns.Length; i++)
                {
                    fullCmd.Parameters.Add(new NpgsqlParameter());
                }
            }

            try
            {
                foreach (var chunk in rows.Chunk(batchSize))
                {
                    var isFullBatch = chunk.Length == batchSize;
                    NpgsqlCommand cmd;
                    if (isFullBatch)
                    {
                        cmd = fullCmd;
                    }
                    else
                    {
                        var partialSql = BuildInsertSql(this.settings.Schema, targetTable, columnList, chunk.Length, columns);
#pragma warning disable CA2100
                        cmd = new NpgsqlCommand(partialSql, conn);
#pragma warning restore CA2100
                        for (var i = 0; i < chunk.Length * columns.Length; i++)
                        {
                            cmd.Parameters.Add(new NpgsqlParameter());
                        }
                    }

                    try
                    {
                        var paramIndex = 0;
                        foreach (var row in chunk)
                        {
                            foreach (var map in mapping)
                            {
                                var rawVal = row.TryGetValue(map.RowKey, out var v) ? v : null;
                                cmd.Parameters[paramIndex++].Value = MapParamValue(rawVal, map.DataType);
                            }
                        }

                        await cmd.ExecuteNonQueryAsync(cancellationToken);
                        result.SuccessCount += chunk.Length;

                        this.logger.LogDebug("Upserted batch of {Count} rows into {Table}", chunk.Length, targetTable);
                    }
                    catch (Exception ex)
                    {
                        this.logger.LogWarning(ex, "Batch of {Count} rows failed for {Table} — retrying row by row", chunk.Length, targetTable);

                        if (conn.State != System.Data.ConnectionState.Open)
                        {
                            await conn.OpenAsync(cancellationToken);
                        }

                        var singleRowSql = BuildInsertSql(this.settings.Schema, targetTable, columnList, 1, columns);
#pragma warning disable CA2100
                        await using var singleCmd = new NpgsqlCommand(singleRowSql, conn);
#pragma warning restore CA2100
                        for (var i = 0; i < columns.Length; i++)
                        {
                            singleCmd.Parameters.Add(new NpgsqlParameter());
                        }

                        foreach (var row in chunk)
                        {
                            var pi = 0;
                            foreach (var map in mapping)
                            {
                                var rawVal = row.TryGetValue(map.RowKey, out var v) ? v : null;
                                singleCmd.Parameters[pi++].Value = MapParamValue(rawVal, map.DataType);
                            }

                            try
                            {
                                await singleCmd.ExecuteNonQueryAsync(cancellationToken);
                                result.SuccessCount++;
                            }
                            catch (Exception rowEx)
                            {
                                var debugInfo = string.Join(", ", mapping.Select(m =>
                                {
                                    row.TryGetValue(m.RowKey, out var val);
                                    return $"{m.RowKey}({m.DataType})={val?.GetType().Name}:{val}";
                                }));
                                this.logger.LogError(rowEx, "Row skipped in {Table}: {Debug}", targetTable, debugInfo);
                                result.ErrorCount++;

                                if (conn.State != System.Data.ConnectionState.Open)
                                {
                                    try
                                    {
                                        await conn.OpenAsync(cancellationToken);
                                    }
                                    catch (Exception reconnectEx)
                                    {
                                        this.logger.LogError(reconnectEx, "Failed to reconnect — aborting remaining batches for {Table}", targetTable);
                                        return result;
                                    }
                                }
                            }
                        }
                    }
                    finally
                    {
                        if (!isFullBatch)
                        {
                            await cmd.DisposeAsync();
                        }
                    }
                }
            }
            finally
            {
                if (fullCmd != null)
                {
                    await fullCmd.DisposeAsync();
                }
            }

            this.logger.LogInformation(
                "SQL publish complete for {Table}: {SuccessCount} succeeded, {ErrorCount} errors",
                targetTable,
                result.SuccessCount,
                result.ErrorCount);

            return result;
        }

        public async Task<int> ReconcileAsync(
            IReadOnlyList<IReadOnlyDictionary<string, object>> currentRows,
            IRisingWaveTableConfig tableConfig,
            CancellationToken cancellationToken = default)
        {
            var pkColumns = tableConfig.EffectivePrimaryKeyColumns;
            var targetTable = tableConfig.ResolvedTargetTable;

            if (pkColumns.Count != 1)
            {
                this.logger.LogWarning(
                    "Reconciliation skipped for {Table} — only single-column primary keys are supported (got {Count}: {Columns})",
                    targetTable,
                    pkColumns.Count,
                    string.Join(", ", pkColumns));
                return 0;
            }

            if (currentRows.Count == 0)
            {
                this.logger.LogWarning(
                    "Reconciliation skipped for {Table} — API returned 0 rows (safety guard: refusing to delete all existing rows)",
                    targetTable);
                return 0;
            }

            if (currentRows.Count > ReconciliationRowLimit)
            {
                this.logger.LogWarning(
                    "Reconciliation skipped for {Table} — {Count} rows exceeds the {Limit}-row limit. Use a full-refresh poll instead.",
                    targetTable,
                    currentRows.Count,
                    ReconciliationRowLimit);
                return 0;
            }

            var pkColumn = pkColumns[0];

            // Build current PK value set. A row whose PK never resolved (an IdExpression that
            // produced nothing arrives as DBNull) must not contribute to it: DBNull.ToString() is
            // the empty string, which would silently enter the set as if it were an id.
            var currentIdSet = new HashSet<string>(StringComparer.Ordinal);
            var unusableIdCount = 0;
            foreach (var row in currentRows)
            {
                var id = row.TryGetValue(pkColumn, out var val) && val is not null and not DBNull
                    ? val.ToString()
                    : null;

                if (string.IsNullOrEmpty(id))
                {
                    unusableIdCount++;
                    continue;
                }

                currentIdSet.Add(id);
            }

            if (currentIdSet.Count == 0)
            {
                this.logger.LogWarning(
                    "Reconciliation skipped for {Table} — none of the {Count} fetched row(s) carried a usable '{Column}' (safety guard: refusing to delete all existing rows)",
                    targetTable,
                    currentRows.Count,
                    pkColumn);
                return 0;
            }

            if (unusableIdCount > 0)
            {
                this.logger.LogWarning(
                    "Reconciliation for {Table}: {Count} fetched row(s) had no usable '{Column}' and were ignored when deciding what is stale",
                    targetTable,
                    unusableIdCount,
                    pkColumn);
            }

            await using var conn = new NpgsqlConnection(this.settings.ConnectionString);
            await conn.OpenAsync(cancellationToken);

            // Guard: table may not exist yet on the very first poll run.
            const string checkSql = @"
                SELECT COUNT(*) FROM information_schema.tables
                WHERE table_schema = @schema AND table_name = @table";
            await using var checkCmd = new NpgsqlCommand(checkSql, conn);
            checkCmd.Parameters.AddWithValue("schema", this.settings.Schema);
            checkCmd.Parameters.AddWithValue("table", targetTable);
            var tableExists = (long)(await checkCmd.ExecuteScalarAsync(cancellationToken) ?? 0L) > 0;

            if (!tableExists)
            {
                this.logger.LogInformation(
                    "Reconciliation skipped — table {Table} does not exist yet",
                    targetTable);
                return 0;
            }

            // Guard: PK column may not exist when the table was created with an older schema.
            // In that case skip and log — operator must run dbt --full-refresh to update the schema.
            const string colCheckSql = @"
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = @schema AND table_name = @table AND column_name = @column";
            await using var colCheckCmd = new NpgsqlCommand(colCheckSql, conn);
            colCheckCmd.Parameters.AddWithValue("schema", this.settings.Schema);
            colCheckCmd.Parameters.AddWithValue("table", targetTable);
            colCheckCmd.Parameters.AddWithValue("column", pkColumn);
            var colExists = (long)(await colCheckCmd.ExecuteScalarAsync(cancellationToken) ?? 0L) > 0;

            if (!colExists)
            {
                this.logger.LogWarning(
                    "Reconciliation skipped — column '{Column}' not found in {Table}. Run: ./deploy.sh <env> --select {Table} --full-refresh",
                    pkColumn,
                    targetTable,
                    targetTable);
                return 0;
            }

            // RisingWave does not support pg_catalog._text (text array parameters), so the
            // UNNEST($1::text[]) pattern cannot be used. Instead: fetch all existing PKs from
            // RisingWave, diff in C#, then delete only the stale rows using scalar parameters.
            var selectSql = $"SELECT CAST(\"{pkColumn}\" AS TEXT) FROM \"{this.settings.Schema}\".\"{targetTable}\"";
#pragma warning disable CA2100
            await using var selectCmd = new NpgsqlCommand(selectSql, conn);
#pragma warning restore CA2100
            var staleIds = new List<string>();
            await using (var reader = await selectCmd.ExecuteReaderAsync(cancellationToken))
            {
                while (await reader.ReadAsync(cancellationToken))
                {
                    var existingId = reader.IsDBNull(0) ? string.Empty : reader.GetString(0);
                    if (!currentIdSet.Contains(existingId))
                    {
                        staleIds.Add(existingId);
                    }
                }
            }

            if (staleIds.Count == 0)
            {
                this.logger.LogInformation(
                    "Reconciliation: {Table} is clean — {Current} rows, 0 stale",
                    targetTable,
                    currentRows.Count);
                return 0;
            }

            // Delete stale rows in batches using scalar parameters (no array type needed).
            const int deleteBatchSize = 500;
            var deletedCount = 0;
            foreach (var batch in staleIds.Chunk(deleteBatchSize))
            {
                var paramPlaceholders = string.Join(", ", batch.Select((_, idx) => $"${idx + 1}"));
                var deleteSql = $"DELETE FROM \"{this.settings.Schema}\".\"{targetTable}\" WHERE CAST(\"{pkColumn}\" AS TEXT) IN ({paramPlaceholders})";
#pragma warning disable CA2100
                await using var deleteCmd = new NpgsqlCommand(deleteSql, conn);
#pragma warning restore CA2100
                foreach (var id in batch)
                {
                    deleteCmd.Parameters.Add(new NpgsqlParameter { Value = id });
                }

                deletedCount += await deleteCmd.ExecuteNonQueryAsync(cancellationToken);
            }

            this.logger.LogInformation(
                "Reconciliation complete for {Table}: {Deleted} stale row(s) deleted ({Current} current rows kept)",
                targetTable,
                deletedCount,
                currentRows.Count);

            return deletedCount;
        }

        private static object MapParamValue(object? rawVal, string dataType) => rawVal switch
        {
            null => DBNull.Value,
            string s when dataType == "timestamp with time zone" =>
                DateTimeOffset.TryParse(s, out var dto) && dto.Year > 1 ? (object)dto.ToUniversalTime() : DBNull.Value,
            DateTime dt when dataType == "timestamp with time zone" && dt.Kind == DateTimeKind.Unspecified =>
                dt.Year > 1 ? (object)DateTime.SpecifyKind(dt, DateTimeKind.Utc) : DBNull.Value,
            DateTime dt when dataType is "timestamp without time zone" =>
                dt.Year > 1 ? (object)dt : DBNull.Value,
            double d when dataType is "bigint" => (object)(long)d,
            double d when dataType is "integer" => (object)(int)d,
            float f when dataType is "bigint" => (object)(long)f,
            float f when dataType is "integer" => (object)(int)f,
            long l when dataType is "integer" => (object)(int)l,
            long l when dataType is "double precision" => (object)(double)l,
            _ => rawVal,
        };

        private static string BuildCreateTableSql(
            string schema,
            string table,
            string[] columns,
            object[] sampleValues,
            IReadOnlyList<string> primaryKeyColumns)
        {
            var sb = new StringBuilder();
            sb.AppendLine($"CREATE TABLE IF NOT EXISTS \"{schema}\".\"{table}\" (");

            for (var i = 0; i < columns.Length; i++)
            {
                var pgType = InferPostgresType(sampleValues[i]);
                sb.Append($"    \"{columns[i]}\" {pgType}");
                sb.AppendLine(i < columns.Length - 1 ? "," : string.Empty);
            }

            if (primaryKeyColumns.Count > 0)
            {
                var pkList = string.Join(", ", primaryKeyColumns.Select(c => $"\"{c}\""));
                sb.AppendLine($"    , PRIMARY KEY ({pkList})");
            }

            sb.Append(')');
            return sb.ToString();
        }

        private static string InferPostgresType(object value) => value switch
        {
            long or int or short => "bigint",
            double or float => "double precision",
            bool => "boolean",
            DateTime => "timestamptz",
            DateTimeOffset => "timestamptz",
            decimal => "numeric",
            byte[] => "bytea",
            _ => "text",
        };

        private static string BuildInsertSql(
            string schema,
            string table,
            string columnList,
            int rowCount,
            string[] columns)
        {
            var colCount = columns.Length;
            var sb = new StringBuilder();
            sb.Append($"INSERT INTO \"{schema}\".\"{table}\" {columnList} VALUES ");

            for (var i = 0; i < rowCount; i++)
            {
                if (i > 0)
                {
                    sb.Append(',');
                }

                var offset = i * colCount;
                sb.Append('(');
                for (var j = 0; j < colCount; j++)
                {
                    if (j > 0)
                    {
                        sb.Append(',');
                    }

                    sb.Append('$').Append(offset + j + 1);
                }

                sb.Append(')');
            }

            return sb.ToString();
        }

        private async Task EnsureTableExistsAsync(
            NpgsqlConnection conn,
            string schema,
            string table,
            string[] columns,
            object[] sampleValues,
            IReadOnlyList<string> primaryKeyColumns,
            CancellationToken cancellationToken)
        {
            const string checkSql = @"
                SELECT COUNT(*) FROM information_schema.tables
                WHERE table_schema = @schema AND table_name = @table";

#pragma warning disable CA2100
            await using var checkCmd = new NpgsqlCommand(checkSql, conn);
#pragma warning restore CA2100
            checkCmd.Parameters.AddWithValue("schema", schema);
            checkCmd.Parameters.AddWithValue("table", table);

            var count = (long)(await checkCmd.ExecuteScalarAsync(cancellationToken) ?? 0L);
            if (count > 0)
            {
                return;
            }

            this.logger.LogInformation("Table {Schema}.{Table} not found — creating", schema, table);

            var ddl = BuildCreateTableSql(schema, table, columns, sampleValues, primaryKeyColumns);
#pragma warning disable CA2100
            await using var createCmd = new NpgsqlCommand(ddl, conn);
#pragma warning restore CA2100
            await createCmd.ExecuteNonQueryAsync(cancellationToken);

            this.logger.LogInformation("Created table {Schema}.{Table}", schema, table);
        }

        private static async Task<Dictionary<string, (string ActualName, string DataType)>> GetTableColumnsAsync(
            NpgsqlConnection conn,
            string schema,
            string table,
            CancellationToken cancellationToken)
        {
            const string sql = @"
                SELECT column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = @schema AND table_name = @table";

#pragma warning disable CA2100
            await using var cmd = new NpgsqlCommand(sql, conn);
#pragma warning restore CA2100
            cmd.Parameters.AddWithValue("schema", schema);
            cmd.Parameters.AddWithValue("table", table);

            var columns = new Dictionary<string, (string, string)>(StringComparer.OrdinalIgnoreCase);
            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var actualName = reader.GetString(0);
                var dataType = reader.GetString(1);
                columns[actualName] = (actualName, dataType);
            }

            return columns;
        }
    }
}
