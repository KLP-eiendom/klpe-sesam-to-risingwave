namespace SinkErrorCollector.Services
{
    using SinkErrorCollector.Models;

    public interface ICloudLoggingPublisher
    {
        Task<int> PublishAsync(IReadOnlyList<SinkFailEvent> events, CancellationToken cancellationToken = default);
    }
}
