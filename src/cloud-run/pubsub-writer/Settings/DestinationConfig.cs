namespace PubSubWriter.Settings
{
    public class DestinationConfig
    {
        public string Name { get; set; }

        public string BaseUrl { get; set; }

        /// <summary>Gets or sets a value indicating whether this destination is enabled for writing.</summary>
        public bool Enabled { get; set; } = true;

        /// <summary>Gets or sets OAuth 2.0 client_credentials config. Set to use Bearer auth.</summary>
        public OAuthConfig OAuth { get; set; }

        /// <summary>
        /// Gets or sets the sync token appended as <c>?sync_token=</c> query parameter.
        /// Set to a non-null value to use sync_token auth. Leave null to omit the parameter.
        /// </summary>
        public string SyncToken { get; set; }

        /// <summary>
        /// Gets or sets the header carrying <see cref="ApiKey"/>, e.g. <c>X-API-Key</c>.
        /// Set together with <see cref="ApiKey"/> to use static API-key auth instead of OAuth.
        /// </summary>
        public string ApiKeyHeader { get; set; }

        /// <summary>
        /// Gets or sets the static API key sent in <see cref="ApiKeyHeader"/>.
        /// Injected at runtime from Vault — left empty in committed appsettings.json.
        /// </summary>
        public string ApiKey { get; set; }
    }
}
