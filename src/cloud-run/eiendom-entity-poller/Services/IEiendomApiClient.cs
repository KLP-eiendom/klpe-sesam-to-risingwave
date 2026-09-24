namespace EiendomEntityPoller.Services
{
    using EiendomEntityPoller.Settings;

    public interface IEiendomApiClient
    {
        Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchEntitiesAsync(
            EntityPollConfig entity,
            CancellationToken cancellationToken = default);
    }
}
