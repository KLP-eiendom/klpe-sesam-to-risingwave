namespace SuperOfficeEntityPoller.Services
{
    using SuperOfficeEntityPoller.Settings;

    public interface ISuperOfficeApiClient
    {
        Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchEntitiesAsync(
            EntityPollConfig entity,
            CancellationToken cancellationToken = default);
    }
}