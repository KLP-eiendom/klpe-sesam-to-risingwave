namespace DaluxEntityPoller.Services
{
    using System.Net.Http.Headers;
    using System.Text.Json;
    using DaluxEntityPoller.Settings;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using RisingWavePollerCommon.Services;

    public class DaluxApiClient : IDaluxApiClient
    {
        // Safety net against a runaway pagination loop if the API ever returns a bookmark that never terminates.
        private const int MaxPages = 1000;

        private readonly HttpClient httpClient;
        private readonly ILogger<DaluxApiClient> logger;
        private readonly DaluxApiSettings settings;

        public DaluxApiClient(
            HttpClient httpClient,
            ILogger<DaluxApiClient> logger,
            IOptions<DaluxApiSettings> settings)
        {
            this.httpClient = httpClient;
            this.logger = logger;
            this.settings = settings.Value;
        }

        public async Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> FetchEntitiesAsync(
            EntityPollConfig entity,
            CancellationToken cancellationToken = default)
        {
            this.httpClient.DefaultRequestHeaders.Remove("X-API-Key");
            this.httpClient.DefaultRequestHeaders.Add("X-API-Key", this.settings.ApiKey);
            this.httpClient.DefaultRequestHeaders.Accept.Clear();
            this.httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

            var rows = new List<Dictionary<string, object>>();
            string bookmark = null;
            var page = 0;

            do
            {
                var url = BuildUrl(entity, bookmark);
                this.logger.LogInformation("Fetching {EntityPath} from {Url}", entity.EntityPath, url);

                var response = await this.httpClient.GetAsync(url, cancellationToken);
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync(cancellationToken);
                using var doc = JsonDocument.Parse(content);
                var root = doc.RootElement;

                if (root.TryGetProperty("items", out var itemsElement) && itemsElement.ValueKind == JsonValueKind.Array)
                {
                    foreach (var item in itemsElement.EnumerateArray())
                    {
                        // Each item wraps the real fields under "data" plus a HATEOAS "links" array — unwrap "data" only.
                        if (!item.TryGetProperty("data", out var dataElement) || dataElement.ValueKind != JsonValueKind.Object)
                        {
                            continue;
                        }

                        var dict = ParseElement(dataElement);

                        if (!string.IsNullOrWhiteSpace(entity.IdExpression))
                        {
                            dict["_id"] = (object)IdExpressionEvaluator.Evaluate(entity.IdExpression, dict) ?? DBNull.Value;
                        }

                        rows.Add(dict);
                    }
                }

                bookmark = root.TryGetProperty("metadata", out var metadataElement) &&
                    metadataElement.TryGetProperty("nextBookmark", out var nextBookmarkElement) &&
                    nextBookmarkElement.ValueKind == JsonValueKind.String
                        ? nextBookmarkElement.GetString()
                        : null;

                page++;
            }
            while (!string.IsNullOrEmpty(bookmark) && page < MaxPages);

            if (page >= MaxPages)
            {
                this.logger.LogWarning(
                    "Stopped paging {EntityPath} after {MaxPages} pages — possible runaway bookmark",
                    entity.EntityPath,
                    MaxPages);
            }

            this.logger.LogInformation(
                "Fetched {Count} rows for {EntityPath} across {Pages} page(s)",
                rows.Count,
                entity.EntityPath,
                page);

            return rows;
        }

        private static Dictionary<string, object> ParseElement(JsonElement element)
        {
            var dict = new Dictionary<string, object>();
            foreach (var prop in element.EnumerateObject())
            {
                dict[prop.Name] = ConvertJsonValue(prop.Value);
            }

            return dict;
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

        private string BuildUrl(EntityPollConfig entity, string bookmark)
        {
            var url = $"{this.settings.BaseUrl.TrimEnd('/')}/{entity.EntityPath.TrimStart('/')}?limit={entity.PageSize}";
            return string.IsNullOrEmpty(bookmark) ? url : $"{url}&bookmark={Uri.EscapeDataString(bookmark)}";
        }
    }
}
