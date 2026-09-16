namespace SinkErrorCollector.Services
{
    using SinkErrorCollector.Models;

    public interface IRisingWaveErrorReader
    {
        Task<IReadOnlyList<SinkFailEvent>> ReadSinkFailEventsAsync(CancellationToken cancellationToken = default);
    }
}
