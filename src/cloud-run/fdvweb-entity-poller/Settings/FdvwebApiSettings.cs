namespace FdvwebEntityPoller.Settings
{
    using RisingWavePollerCommon.Settings;

    public class FdvwebApiSettings : IOAuthApiSettings
    {
        public string BaseUrl { get; set; } = string.Empty;

        public string ClientId { get; set; } = string.Empty;

        public string ClientSecret { get; set; } = string.Empty;

        public string Scope { get; set; } = string.Empty;

        public string TokenUrl { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the list of FDV-web entities to poll and push to RisingWave.
        /// </summary>
        public List<EntityPollConfig> Entities { get; set; } = new();
    }
}
