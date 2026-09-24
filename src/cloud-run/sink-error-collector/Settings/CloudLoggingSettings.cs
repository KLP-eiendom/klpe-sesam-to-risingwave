namespace SinkErrorCollector.Settings
{
    public class CloudLoggingSettings
    {
        public string ProjectId { get; set; } = string.Empty;

        public string LogId { get; set; } = "risingwave-sink-errors";
    }
}
