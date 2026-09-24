namespace DaluxEntityPoller.Services
{
    using DaluxEntityPoller.Settings;

    public interface IDaluxApiClient
    {
        Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchEntitiesAsync(
            EntityPollConfig entity,
            CancellationToken cancellationToken = default);
    }
}
