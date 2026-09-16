namespace FdvwebEntityPoller.Services
{
    using System.Net.Http.Headers;
    using System.Text.Json;
    using FdvwebEntityPoller.Settings;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using RisingWavePollerCommon.Services;

    public class FdvwebApiClient : IFdvwebApiClient
    {
        private readonly HttpClient httpClient;
        private readonly ILogger<FdvwebApiClient> logger;
        private readonly FdvwebApiSettings settings;
        private readonly IOAuthTokenService oAuthTokenService;

        public FdvwebApiClient(
            HttpClient httpClient,
            ILogger<FdvwebApiClient> logger,
            IOptions<FdvwebApiSettings> settings,
            IOAuthTokenService oAuthTokenService)
        {
            this.httpClient = httpClient;
            this.logger = logger;
            this.settings = settings.Value;
            this.oAuthTokenService = oAuthTokenService;
        }

        public async Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchEntitiesAsync(
            EntityPollConfig entity,
            CancellationToken cancellationToken = default)
        {
            var token = await this.oAuthTokenService.GetAccessTokenAsync(cancellationToken);
            var url = $"{this.settings.BaseUrl.TrimEnd('/')}/{entity.EntityPath.TrimStart('/')}";

            this.logger.LogInformation("Fetching {EntityPath} from {Url}", entity.EntityPath, url);

            this.httpClient.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", token);
            this.httpClient.DefaultRequestHeaders.Accept.Clear();
            this.httpClient.DefaultRequestHeaders.Accept.Add(
                new MediaTypeWithQualityHeaderValue("application/json"));

            var response = await this.httpClient.GetAsync(url, cancellationToken);
            response.EnsureSuccessStatusCode();

            var content = await response.Content.ReadAsStringAsync(cancellationToken);
            var elements = JsonSerializer.Deserialize<List<JsonElement>>(content) ?? new();

            var rows = new List<Dictionary<string, object>>(elements.Count);
            foreach (var element in elements)
            {
                var dict = new Dictionary<string, object>();
                foreach (var prop in element.EnumerateObject())
                {
                    dict[prop.Name] = ConvertJsonValue(prop.Value);
                }

                if (!string.IsNullOrWhiteSpace(entity.IdExpression))
                {
                    dict["_id"] = (object)IdExpressionEvaluator.Evaluate(entity.IdExpression, dict) ?? DBNull.Value;
                }

                rows.Add(dict);
            }

            this.logger.LogInformation(
                "Fetched {Count} rows for {EntityPath}",
                rows.Count,
                entity.EntityPath);

            return rows;
        }

        private static object ConvertJsonValue(JsonElement element) => element.ValueKind switch
        {
            JsonValueKind.String => (object)(element.GetString() ?? string.Empty),
            JsonValueKind.Number when element.TryGetInt64(out var l) => l,
            JsonValueKind.Number => element.GetDouble(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Null => DBNull.Value,
            _ => element.GetRawText(),
        };
    }
}
