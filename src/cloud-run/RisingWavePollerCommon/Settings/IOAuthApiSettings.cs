namespace RisingWavePollerCommon.Settings
{
    public interface IOAuthApiSettings
    {
        string TokenUrl { get; }

        string ClientId { get; }

        string ClientSecret { get; }

        string Scope { get; }
    }
}
