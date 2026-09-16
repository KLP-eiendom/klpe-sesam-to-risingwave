namespace SinkErrorCollector.Models
{
    public sealed record SinkFailEvent
    {
        public string UniqueId { get; init; } = string.Empty;

        public DateTimeOffset Timestamp { get; init; }

        public string SinkId { get; init; } = string.Empty;

        public string SinkName { get; init; } = string.Empty;

        public string Connector { get; init; } = string.Empty;

        public string ErrorMessage { get; init; } = string.Empty;

        public string RawInfoJson { get; init; } = string.Empty;
    }
}
