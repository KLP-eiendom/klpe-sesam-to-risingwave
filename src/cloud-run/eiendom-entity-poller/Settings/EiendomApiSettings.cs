namespace EiendomEntityPoller.Settings
{
    using RisingWavePollerCommon.Settings;

    public class EiendomApiSettings : IOAuthApiSettings
    {
        /// <summary>
        /// Gets or sets the base URL of the Eiendom API, e.g. "https://api-dev.klpeiendom.no".
        /// </summary>
        public string BaseUrl { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the base URL north cluster of the Eiendom API, e.g. "https://api-dev.mittleieforhold.no".
        /// </summary>
        public string BaseUrlNorth { get; set; } = string.Empty;

        public string ClientId { get; set; } = string.Empty;

        public string ClientSecret { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the OAuth2 scope(s) to request, space-separated.
        /// Default matches the eiendom-api Sesam system scopes.
        /// </summary>
        public string Scope { get; set; } = "prosjektapi";

        /// <summary>
        /// Gets or sets the full token endpoint URL, e.g. "https://auth-dev.klpeiendom.no/connect/token".
        /// </summary>
        public string TokenUrl { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the list of Eiendom API entities to poll and push to RisingWave.
        /// </summary>
        public List<EntityPollConfig> Entities { get; set; } = new();
    }
}
