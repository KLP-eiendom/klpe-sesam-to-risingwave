namespace BigQueryEntityPoller.Services
{
    using BigQueryEntityPoller.Settings;
    using Google.Apis.Auth.OAuth2;
    using Google.Cloud.BigQuery.V2;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using RisingWavePollerCommon.Services;

    public sealed class BigQuerySourceService : IBigQuerySourceService
    {
        private const int HttpTimeoutSeconds = 300;

        private readonly ILogger<BigQuerySourceService> logger;
        private readonly BigQuerySettings bigQuerySettings;
        private readonly GcpCredentialSettings credentialSettings;

        // Lazy ensures the client is created once even under parallel calls; no disposable fields.
        private readonly Lazy<Task<BigQueryClient>> clientTask;

        public BigQuerySourceService(
            ILogger<BigQuerySourceService> logger,
            IOptions<BigQuerySettings> bigQuerySettings,
            IOptions<GcpCredentialSettings> credentialSettings)
        {
            this.logger = logger;
            this.bigQuerySettings = bigQuerySettings.Value;
            this.credentialSettings = credentialSettings.Value;
            this.clientTask = new Lazy<Task<BigQueryClient>>(this.CreateClientAsync);

            this.logger.LogInformation(
                "BigQuery source configured: project={ProjectId}, {TableCount} table(s) to poll",
                this.bigQuerySettings.ProjectId,
                this.bigQuerySettings.Tables.Count);
        }

        public async Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchRowsAsync(
            TablePollConfig table,
            CancellationToken cancellationToken = default)
        {
            var client = await this.clientTask.Value;

            var sql = BuildQuery(this.bigQuerySettings.ProjectId, table);
            this.logger.LogDebug("Executing BigQuery query: {Sql}", sql);

            var results = await client.ExecuteQueryAsync(sql, parameters: null);

            var columns = results.Schema.Fields.Select(f => f.Name).ToList();
            var rows = new List<IReadOnlyDictionary<string, object>>();

            foreach (var row in results)
            {
                var dict = new Dictionary<string, object>(columns.Count);
                foreach (var column in columns)
                {
                    dict[column] = NormalizeValue(row[column]);
                }

                if (!string.IsNullOrWhiteSpace(table.IdExpression))
                {
                    var id = IdExpressionEvaluator.Evaluate(table.IdExpression, dict);
                    dict["_id"] = (object)id ?? DBNull.Value;
                }

                if (!string.IsNullOrWhiteSpace(table.ActiveUntilColumn))
                {
                    dict["_is_active"] = ComputeIsActive(dict, table.ActiveUntilColumn);
                }

                rows.Add(dict);
            }

            this.logger.LogInformation(
                "BigQuery returned {RowCount} rows with {ColumnCount} columns from {DatasetId}.{TableId}",
                rows.Count,
                columns.Count,
                table.DatasetId,
                table.TableId);

            return rows;
        }

        private static bool ComputeIsActive(IReadOnlyDictionary<string, object> row, string activeUntilColumn)
        {
            if (!row.TryGetValue(activeUntilColumn, out var value) || value is DBNull || value is null)
            {
                return true;
            }

            var expiryDate = value switch
            {
                DateTime dt => dt.Date,
                DateTimeOffset dto => dto.UtcDateTime.Date,
                _ => null as DateTime?,
            };

            return expiryDate == null || expiryDate.Value >= DateTime.UtcNow.Date;
        }

        private static string BuildQuery(string projectId, TablePollConfig table)
        {
            var sql = $"SELECT * FROM `{projectId}.{table.DatasetId}.{table.TableId}`";

            if (!string.IsNullOrWhiteSpace(table.WhereClause))
            {
                sql += $" WHERE {table.WhereClause}";
            }

            return sql;
        }

        private static object NormalizeValue(object value)
        {
            return value switch
            {
                // BigQuery TIMESTAMP is returned as DateTimeOffset by the V2 library.
                // Convert to UTC DateTime so Npgsql maps it to timestamptz correctly.
                DateTimeOffset dto => dto.UtcDateTime,

                // Convert NUMERIC to double so Npgsql sends float8 — a direct match for
                // DOUBLE PRECISION staging columns, avoiding numeric→float8 implicit cast in RisingWave.
                BigQueryNumeric bqn => (double)(decimal)bqn,

                // Some D365 BigQuery columns were originally written by Sesam and store datetimes
                // as strings with the Sesam ~t prefix (e.g. "~t2021-08-20T15:51:34Z").
                // Strip the prefix and parse so Npgsql sends a proper DateTime, not a raw string
                // that would cause str_to_timestamptz to fail in RisingWave.
                string s when s.StartsWith("~t", StringComparison.Ordinal) =>
                    DateTimeOffset.TryParse(s.AsSpan(2), null, System.Globalization.DateTimeStyles.RoundtripKind, out var dto)
                        ? (object)dto.UtcDateTime
                        : DBNull.Value,

                _ => value,
            };
        }

        private async Task<BigQueryClient> CreateClientAsync()
        {
            BigQueryClient client;

            if (!string.IsNullOrEmpty(this.credentialSettings.Value))
            {
                var credentials = GoogleCredential.FromJson(this.credentialSettings.Value);
                client = await BigQueryClient.CreateAsync(this.bigQuerySettings.ProjectId, credentials);
            }
            else
            {
                // Fall back to Application Default Credentials (ADC).
                // On Cloud Run this is satisfied automatically via Workload Identity or the attached service account.
                client = await BigQueryClient.CreateAsync(this.bigQuerySettings.ProjectId);
            }

            client.Service.HttpClient.Timeout = TimeSpan.FromSeconds(HttpTimeoutSeconds);
            return client;
        }
    }
}
