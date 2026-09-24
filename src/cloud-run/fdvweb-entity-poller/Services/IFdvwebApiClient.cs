namespace FdvwebEntityPoller.Services
{
    using FdvwebEntityPoller.Settings;

    public interface IFdvwebApiClient
    {
        Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchEntitiesAsync(
            EntityPollConfig entity,
            CancellationToken cancellationToken = default);
    }
}
