namespace BigQueryEntityPoller.Services
{
    using BigQueryEntityPoller.Settings;

    public interface IBigQuerySourceService
    {
        Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchRowsAsync(
            TablePollConfig table,
            CancellationToken cancellationToken = default);
    }
}
