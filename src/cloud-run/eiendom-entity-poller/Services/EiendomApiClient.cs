namespace EiendomEntityPoller.Services
{
    using System.Net.Http.Headers;
    using System.Text.Json;
    using EiendomEntityPoller.Settings;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using RisingWavePollerCommon.Services;

    public class EiendomApiClient : IEiendomApiClient
    {
        private readonly HttpClient httpClient;
        private readonly ILogger<EiendomApiClient> logger;
        private readonly EiendomApiSettings settings;
        private readonly IOAuthTokenService oAuthTokenService;

        public EiendomApiClient(
            HttpClient httpClient,
            ILogger<EiendomApiClient> logger,
            IOptions<EiendomApiSettings> settings,
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
            var url = entity.UseNorthCluster ?
                $"{this.settings.BaseUrlNorth.TrimEnd('/')}/{entity.EntityPath}" :
                $"{this.settings.BaseUrl.TrimEnd('/')}/{entity.EntityPath}";

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

            var rows = string.IsNullOrWhiteSpace(entity.ChildrenPath)
                ? this.FlattenDirect(elements, entity)
                : this.FlattenChildren(elements, entity);

            this.logger.LogInformation(
                "Fetched {Count} rows for {EntityPath}", rows.Count, entity.EntityPath);

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

        private IReadOnlyList<IReadOnlyDictionary<string, object>> FlattenDirect(
            List<JsonElement> elements,
            EntityPollConfig entity)
        {
            var rows = new List<Dictionary<string, object>>(elements.Count);

            foreach (var element in elements)
            {
                var dict = ParseElement(element);

                if (!string.IsNullOrWhiteSpace(entity.IdExpression))
                {
                    dict["_id"] = (object)IdExpressionEvaluator.Evaluate(entity.IdExpression, dict) ?? DBNull.Value;
                }

                rows.Add(dict);
            }

            return rows;
        }

        private IReadOnlyList<IReadOnlyDictionary<string, object>> FlattenChildren(
            List<JsonElement> elements,
            EntityPollConfig entity)
        {
            var rows = new List<Dictionary<string, object>>();
            var parentTargetField = string.IsNullOrWhiteSpace(entity.ParentKeyTargetField)
                ? entity.ParentKeyField
                : entity.ParentKeyTargetField;

            foreach (var parentElement in elements)
            {
                var parentDict = ParseElement(parentElement);

                if (!parentDict.TryGetValue(entity.ChildrenPath, out var childrenRaw) ||
                    childrenRaw is not string childrenJson)
                {
                    this.logger.LogDebug(
                        "Parent entity has no '{ChildrenPath}' array — skipping", entity.ChildrenPath);
                    continue;
                }

                List<JsonElement> children;
                try
                {
                    children = JsonSerializer.Deserialize<List<JsonElement>>(childrenJson) ?? new();
                }
                catch (JsonException ex)
                {
                    this.logger.LogWarning(ex, "Could not parse children array at '{ChildrenPath}'", entity.ChildrenPath);
                    continue;
                }

                var parentKeyValue = string.IsNullOrWhiteSpace(entity.ParentKeyField) || !parentDict.TryGetValue(entity.ParentKeyField, out var pkv)
                    ? null
                    : pkv;

                foreach (var childElement in children)
                {
                    var childDict = ParseElement(childElement);

                    if (!string.IsNullOrWhiteSpace(parentTargetField) && parentKeyValue != null)
                    {
                        childDict[parentTargetField] = parentKeyValue;
                    }

                    if (!string.IsNullOrWhiteSpace(entity.IdExpression))
                    {
                        childDict["_id"] = (object)IdExpressionEvaluator.Evaluate(entity.IdExpression, childDict) ?? DBNull.Value;
                    }

                    rows.Add(childDict);
                }
            }

            return rows;
        }
    }
}
