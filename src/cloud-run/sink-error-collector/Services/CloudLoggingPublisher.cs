namespace SinkErrorCollector.Services
{
    using System.Text.Json;
    using Google.Api;
    using Google.Cloud.Logging.Type;
    using Google.Cloud.Logging.V2;
    using Google.Protobuf.WellKnownTypes;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using SinkErrorCollector.Models;
    using SinkErrorCollector.Settings;

    public sealed class CloudLoggingPublisher : ICloudLoggingPublisher
    {
        private readonly ILogger<CloudLoggingPublisher> logger;
        private readonly CloudLoggingSettings settings;
        private readonly LoggingServiceV2Client client;

        public CloudLoggingPublisher(
            ILogger<CloudLoggingPublisher> logger,
            IOptions<CloudLoggingSettings> settings)
        {
            this.logger = logger;
            this.settings = settings.Value;
            this.client = LoggingServiceV2Client.Create();
        }

        public async Task<int> PublishAsync(IReadOnlyList<SinkFailEvent> events, CancellationToken cancellationToken = default)
        {
            if (events.Count == 0)
            {
                return 0;
            }

            var logName = new LogName(this.settings.ProjectId, this.settings.LogId);
            var resource = new MonitoredResource { Type = "global" };
            var entries = events.Select(e => BuildLogEntry(logName, e)).ToList();

            await this.client.WriteLogEntriesAsync(
                logName,
                resource,
                labels: null,
                entries,
                cancellationToken);

            this.logger.LogInformation(
                "Wrote {Count} LogEntries to projects/{Project}/logs/{LogId}",
                entries.Count,
                this.settings.ProjectId,
                this.settings.LogId);

            return entries.Count;
        }

        private static LogEntry BuildLogEntry(LogName logName, SinkFailEvent e)
        {
            var payload = new
            {
                uniqueId = e.UniqueId,
                sinkId = e.SinkId,
                sinkName = e.SinkName,
                connector = e.Connector,
                error = e.ErrorMessage,
                rawInfo = e.RawInfoJson,
            };

            var entry = new LogEntry
            {
                LogName = logName.ToString(),
                Severity = LogSeverity.Error,
                Timestamp = Timestamp.FromDateTimeOffset(e.Timestamp),

                // unique_id is the canonical, stable PK from rw_event_logs — perfect insertId.
                // Cloud Logging dedupes on (logName, insertId) within a 1-hour window,
                // which covers overlapping 5-min poll reads against the rolling 10-row buffer.
                InsertId = e.UniqueId,
                JsonPayload = Struct.Parser.ParseJson(JsonSerializer.Serialize(payload)),
            };

            entry.Labels.Add("event_type", "SINK_FAIL");
            if (!string.IsNullOrEmpty(e.SinkId))
            {
                entry.Labels.Add("sink_id", e.SinkId);
            }

            if (!string.IsNullOrEmpty(e.SinkName))
            {
                entry.Labels.Add("sink_name", e.SinkName);
            }

            if (!string.IsNullOrEmpty(e.Connector))
            {
                entry.Labels.Add("connector", e.Connector);
            }

            return entry;
        }
    }
}
