namespace SuperOfficeEntityPoller.Settings
{
    using RisingWavePollerCommon.Settings;

    public class KdiApiSettings : IOAuthApiSettings
    {
        public string KdiApiBaseUrl { get; set; }

        public string KdiApiBaseUrlNorth { get; set; }

        public string ClientId { get; set; }

        public string ClientSecret { get; set; }

        public string Scope { get; set; } = "superofficeapi";

        public string TokenUrl { get; set; }

        /// <summary>
        /// Gets or sets the list of SuperOffice entities to poll and push to RisingWave.
        /// </summary>
        public List<EntityPollConfig> Entities { get; set; } = new();
    }
}