namespace MysqlEntityPoller.Services
{
    using Microsoft.Extensions.Logging;
    using MySqlConnector;
    using MysqlEntityPoller.Settings;
    using RisingWavePollerCommon.Services;

    public class MysqlTableReader : IMysqlTableReader
    {
        private readonly ILogger<MysqlTableReader> logger;

        public MysqlTableReader(ILogger<MysqlTableReader> logger)
        {
            this.logger = logger;
        }

        public async Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> ReadTableAsync(
            string host,
            int port,
            string database,
            string username,
            string password,
            TablePollConfig tableConfig,
            CancellationToken cancellationToken = default)
        {
            var csb = new MySqlConnectionStringBuilder
            {
                Server = host,
                Port = (uint)port,
                Database = database,
                UserID = username,
                Password = password,
                SslMode = MySqlSslMode.Preferred,
                AllowPublicKeyRetrieval = true,
                TreatTinyAsBoolean = true,
            };

            this.logger.LogInformation(
                "Reading {Table} from {Database}@{Host}",
                tableConfig.TableName,
                database,
                host);

            var rows = new List<IReadOnlyDictionary<string, object>>();
            await using var conn = new MySqlConnection(csb.ConnectionString);
            await conn.OpenAsync(cancellationToken);

#pragma warning disable CA2100
            await using var cmd = new MySqlCommand($"SELECT * FROM `{tableConfig.TableName}`", conn);
#pragma warning restore CA2100

            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                var row = new Dictionary<string, object>();
                for (var i = 0; i < reader.FieldCount; i++)
                {
                    var name = reader.GetName(i);
                    var value = reader.IsDBNull(i) ? null : NormalizeMySqlValue(reader.GetValue(i));
                    row[name] = value;
                }

                if (!string.IsNullOrWhiteSpace(tableConfig.IdExpression))
                {
                    row["_id"] = (object)IdExpressionEvaluator.Evaluate(tableConfig.IdExpression, row) ?? DBNull.Value;
                }

                rows.Add(row);
            }

            this.logger.LogInformation("Read {Count} rows from {Table}", rows.Count, tableConfig.TableName);

            return rows;
        }

        private static object NormalizeMySqlValue(object value) => value switch
        {
            ulong ul => (long)ul,
            uint ui => (long)ui,
            ushort us => (long)us,
            byte b => (long)b,
            sbyte sb => sb != 0,

            // MySQL zero-datetime (0000-00-00) arrives as DateTime.MinValue — out of range for RisingWave
            DateTime dt when dt.Year <= 1 => DBNull.Value,
            _ => value,
        };
    }
}
