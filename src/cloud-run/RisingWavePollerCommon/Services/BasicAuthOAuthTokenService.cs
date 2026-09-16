namespace RisingWavePollerCommon.Services
{
    using System.Text;
    using System.Text.Json;
    using System.Text.Json.Serialization;
    using RisingWavePollerCommon.Settings;
    using Microsoft.Extensions.Logging;

    public class BasicAuthOAuthTokenService : IOAuthTokenService
    {
        private readonly HttpClient httpClient;
        private readonly ILogger<BasicAuthOAuthTokenService> logger;
        private readonly IOAuthApiSettings settings;
        private string cachedToken;
        private DateTimeOffset tokenExpiry;

        public BasicAuthOAuthTokenService(
            HttpClient httpClient,
            ILogger<BasicAuthOAuthTokenService> logger,
            IOAuthApiSettings settings)
        {
            this.httpClient = httpClient;
            this.logger = logger;
            this.settings = settings;
        }

        public async Task<string> GetAccessTokenAsync(CancellationToken cancellationToken = default)
        {
            if (this.cachedToken != null && DateTimeOffset.UtcNow < this.tokenExpiry)
            {
                return this.cachedToken;
            }

            this.logger.LogInformation("Requesting new OAuth2 access token (Basic auth) from {TokenUrl}", this.settings.TokenUrl);

            var parameters = new Dictionary<string, string>
            {
                { "grant_type", "client_credentials" },
            };

            if (!string.IsNullOrEmpty(this.settings.Scope))
            {
                parameters["scope"] = this.settings.Scope;
            }

            var credentials = Convert.ToBase64String(
                Encoding.UTF8.GetBytes($"{this.settings.ClientId}:{this.settings.ClientSecret}"));

            var request = new HttpRequestMessage(HttpMethod.Post, this.settings.TokenUrl)
            {
                Content = new FormUrlEncodedContent(parameters),
            };
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", credentials);

            var response = await this.httpClient.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            var tokenResponse = JsonSerializer.Deserialize<TokenResponse>(json)
                ?? throw new InvalidOperationException("Failed to deserialize OAuth2 token response");

            this.cachedToken = tokenResponse.AccessToken;
            this.tokenExpiry = DateTimeOffset.UtcNow.AddSeconds(tokenResponse.ExpiresIn - 10);

            this.logger.LogInformation(
                "Obtained OAuth2 access token, expires in {ExpiresIn}s", tokenResponse.ExpiresIn);

            return this.cachedToken;
        }

        private class TokenResponse
        {
            [JsonPropertyName("access_token")]
            public string AccessToken { get; set; }

            [JsonPropertyName("expires_in")]
            public int ExpiresIn { get; set; }
        }
    }
}
