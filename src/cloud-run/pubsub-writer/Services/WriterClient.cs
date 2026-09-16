namespace PubSubWriter.Services
{
    using System.Net.Http.Headers;
    using System.Text;
    using System.Text.Json;
    using Microsoft.Extensions.Logging;
    using PubSubWriter.Settings;

    public class WriterClient : IWriterClient
    {
        private readonly HttpClient httpClient;
        private readonly ILogger<WriterClient> logger;
        private readonly Dictionary<string, CachedToken> tokenCache = new();

        public WriterClient(HttpClient httpClient, ILogger<WriterClient> logger)
        {
            this.httpClient = httpClient;
            this.logger = logger;
        }

        public async Task<bool> SendAsync(
            string json,
            HttpMethod method,
            DestinationConfig destination,
            string url,
            CancellationToken cancellationToken)
        {
            if (destination.SyncToken != null)
            {
                url += $"?sync_token={destination.SyncToken}";
            }

            string bearerToken = null;
            if (destination.OAuth != null)
            {
                bearerToken = await this.GetOrRefreshTokenAsync(destination.OAuth, cancellationToken);
            }

            using var content = new StringContent(json, Encoding.UTF8, "application/json");

            using var request = new HttpRequestMessage(method, url);
            if (bearerToken != null)
            {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);
            }

            if (!string.IsNullOrEmpty(destination.ApiKeyHeader) && !string.IsNullOrEmpty(destination.ApiKey))
            {
                request.Headers.Add(destination.ApiKeyHeader, destination.ApiKey);
            }

            request.Content = content;

            var response = await this.httpClient.SendAsync(request, cancellationToken);

            if (response.IsSuccessStatusCode)
            {
                return true;
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            this.logger.LogError(
                "{Method} {Url} returned {StatusCode}: {Body}. Request payload: {Payload}",
                method.Method,
                url,
                (int)response.StatusCode,
                body,
                json);
            return false;
        }

        private async Task<string> GetOrRefreshTokenAsync(OAuthConfig config, CancellationToken cancellationToken)
        {
            var cacheKey = $"{config.TokenUrl}|{config.ClientId}";

            if (this.tokenCache.TryGetValue(cacheKey, out var cached) && cached.Expiry > DateTimeOffset.UtcNow.AddMinutes(1))
            {
                return cached.Token;
            }

            using var formContent = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("grant_type", "client_credentials"),
                new KeyValuePair<string, string>("client_id", config.ClientId),
                new KeyValuePair<string, string>("client_secret", config.ClientSecret),
                new KeyValuePair<string, string>("scope", config.Scope),
            });

            var response = await this.httpClient.PostAsync(config.TokenUrl, formContent, cancellationToken);
            response.EnsureSuccessStatusCode();

            var jsonText = await response.Content.ReadAsStringAsync(cancellationToken);
            using var doc = JsonDocument.Parse(jsonText);
            var root = doc.RootElement;

            var accessToken = root.GetProperty("access_token").GetString();
            var expiresIn = root.TryGetProperty("expires_in", out var expProp) ? expProp.GetInt32() : 3600;

            this.tokenCache[cacheKey] = new CachedToken(accessToken, DateTimeOffset.UtcNow.AddSeconds(expiresIn - 30));
            return accessToken;
        }

        private sealed class CachedToken
        {
            public CachedToken(string token, DateTimeOffset expiry)
            {
                this.Token = token;
                this.Expiry = expiry;
            }

            public string Token { get; }

            public DateTimeOffset Expiry { get; }
        }
    }
}
