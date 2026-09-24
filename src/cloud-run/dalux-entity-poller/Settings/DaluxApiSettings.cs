namespace DaluxEntityPoller.Settings
{
    public class DaluxApiSettings
    {
        /// <summary>
        /// Gets or sets the base URL of the Dalux Field Management API, e.g. "https://fm-api.dalux.com/api".
        /// </summary>
        public string BaseUrl { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the static API key sent as the <c>X-API-Key</c> header on every request.
        /// Injected at runtime from Vault — left empty in committed appsettings.json.
        /// </summary>
        public string ApiKey { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the list of Dalux API entities to poll and push to RisingWave.
        /// </summary>
        public List<EntityPollConfig> Entities { get; set; } = new();
    }
}
