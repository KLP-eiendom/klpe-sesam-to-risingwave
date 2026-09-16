namespace RisingWavePollerCommon.Services
{
    public interface IOAuthTokenService
    {
        Task<string> GetAccessTokenAsync(CancellationToken cancellationToken = default);
    }
}
