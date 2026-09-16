namespace SinkErrorCollector.Services
{
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Logging;
    using Npgsql;
    using SinkErrorCollector.Models;

    public sealed class RisingWaveErrorReader : IRisingWaveErrorReader
    {
        // The `info` JSONB column carries the full EventLog proto serialized via serde_json.
        // For an EventSinkFail variant the inner fields live at event.sinkFail.{sinkId,sinkName,connector,error}.
        // COALESCE handles both camelCase (default) and snake_case serializers across RW versions.
        private const string ReadSinkFailSql = @"
            SELECT
                e.unique_id,
                e.timestamp,
                COALESCE(e.info #>> '{event,sinkFail,sinkId}',
                         e.info #>> '{event,sink_fail,sink_id}') AS sink_id,
                COALESCE(e.info #>> '{event,sinkFail,sinkName}',
                         e.info #>> '{event,sink_fail,sink_name}') AS sink_name,
                COALESCE(e.info #>> '{event,sinkFail,connector}',
                         e.info #>> '{event,sink_fail,connector}') AS connector,
                COALESCE(e.info #>> '{event,sinkFail,error}',
                         e.info #>> '{event,sink_fail,error}') AS error_message,
                e.info::TEXT AS info_json
            FROM rw_catalog.rw_event_logs e
            WHERE e.event_type = 'SINK_FAIL'
              AND e.timestamp > NOW() - INTERVAL '15 MINUTE'
            ORDER BY e.timestamp DESC";

        private readonly ILogger<RisingWaveErrorReader> logger;
        private readonly string connectionString;

        public RisingWaveErrorReader(
            ILogger<RisingWaveErrorReader> logger,
            IConfiguration configuration)
        {
            this.logger = logger;

            // The collector connects once per 5-minute polling cycle; a pooled idle socket gets
            // dropped by the peer between cycles (EndOfStreamException on the next read), so
            // pooling is disabled to open a fresh connection every cycle.
            var builder = new NpgsqlConnectionStringBuilder(configuration.GetConnectionString("RisingWave"))
            {
                Pooling = false,
            };
            this.connectionString = builder.ConnectionString;

            this.logger.LogInformation("RisingWave error reader configured with connection string (pooling disabled)");
        }

        public async Task<IReadOnlyList<SinkFailEvent>> ReadSinkFailEventsAsync(CancellationToken cancellationToken = default)
        {
            await using var conn = new NpgsqlConnection(this.connectionString);
            await conn.OpenAsync(cancellationToken);

            await using var cmd = new NpgsqlCommand(ReadSinkFailSql, conn);

            var events = new List<SinkFailEvent>();
            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                events.Add(new SinkFailEvent
                {
                    UniqueId = reader.GetString(0),
                    Timestamp = reader.GetFieldValue<DateTime>(1).ToUniversalTime(),
                    SinkId = reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                    SinkName = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                    Connector = reader.IsDBNull(4) ? string.Empty : reader.GetString(4),
                    ErrorMessage = reader.IsDBNull(5) ? string.Empty : reader.GetString(5),
                    RawInfoJson = reader.GetString(6),
                });
            }

            return events;
        }
    }
}
