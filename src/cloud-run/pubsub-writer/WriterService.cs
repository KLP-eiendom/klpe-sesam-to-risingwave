namespace PubSubWriter
{
    using System.Collections.Concurrent;
    using System.Linq;
    using System.Text;
    using System.Text.Json;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Logging;
    using PubSubWriter.Services;
    using PubSubWriter.Settings;

    public class WriterService : BackgroundService
    {
        private readonly ILogger<WriterService> logger;
        private readonly IPubSubService pubSubService;
        private readonly IWriterClient writerClient;
        private readonly WriterSettings settings;
        private readonly IHostApplicationLifetime lifetime;
        private readonly ConcurrentDictionary<(string Subscription, string PrimaryKeyVal, string NameVal), int> processedCounters = new();
        private readonly ConcurrentDictionary<(string Subscription, string PrimaryKeyVal), string> lastSentPayloads = new();

        public WriterService(
            ILogger<WriterService> logger,
            IPubSubService pubSubService,
            IWriterClient writerClient,
            WriterSettings settings,
            IHostApplicationLifetime lifetime)
        {
            this.logger = logger;
            this.pubSubService = pubSubService;
            this.writerClient = writerClient;
            this.settings = settings;
            this.lifetime = lifetime;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            this.logger.LogInformation(
                "Starting PubSub writer daemon — {Count} subscription(s) configured",
                this.settings.Subscriptions.Count);

            var destinations = this.settings.Destinations.ToDictionary(d => d.Name);

            while (!stoppingToken.IsCancellationRequested)
            {
                int successCount = 0;
                int skippedCount = 0;
                int errorCount = 0;
                bool hadActivity = false;

                try
                {
                    foreach (var subscription in this.settings.Subscriptions)
                    {
                        if (!destinations.TryGetValue(subscription.Destination, out var destination))
                        {
                            this.logger.LogError(
                                "Destination '{Destination}' not found for {SubscriptionId} — skipping.",
                                subscription.Destination,
                                subscription.SubscriptionId);
                            errorCount++;
                            continue;
                        }

                        if (destination.SyncToken != null && string.IsNullOrWhiteSpace(destination.SyncToken))
                        {
                            this.logger.LogWarning(
                                "SyncToken not configured for destination '{Destination}' ({SubscriptionId}) — skipping.",
                                destination.Name,
                                subscription.SubscriptionId);
                            continue;
                        }

                        if (!string.IsNullOrEmpty(destination.ApiKeyHeader) && string.IsNullOrWhiteSpace(destination.ApiKey))
                        {
                            // Sending anyway would fire unauthenticated writes at the destination and
                            // burn the messages on a 401. Better to leave them unacked for the
                            // dead-letter topic and say why.
                            this.logger.LogWarning(
                                "ApiKey not configured for destination '{Destination}' ({SubscriptionId}) — skipping.",
                                destination.Name,
                                subscription.SubscriptionId);
                            continue;
                        }

                        try
                        {
                            var result = await this.ProcessSubscriptionAsync(subscription, destination, stoppingToken);
                            successCount += result.Success;
                            skippedCount += result.Skipped;
                            errorCount += result.Error;

                            if (result.Success > 0 || result.Skipped > 0 || result.Error > 0)
                            {
                                hadActivity = true;
                            }
                        }
                        catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
                        {
                            this.logger.LogError(ex, "Failed to process subscription {SubscriptionId}", subscription.SubscriptionId);
                            errorCount++;
                        }
                    }

                    if (hadActivity)
                    {
                        this.logger.LogInformation(
                            "Writer cycle completed: {SuccessCount} posted, {SkippedCount} skipped (deleted or unchanged), {ErrorCount} errors",
                            successCount,
                            skippedCount,
                            errorCount);
                    }
                }
                catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
                {
                    this.logger.LogError(ex, "Writer failed with unhandled exception in cycle");
                }

                if (!hadActivity && !stoppingToken.IsCancellationRequested)
                {
                    // Delay for 5 seconds when idle to avoid rate-limiting Pub/Sub Pull API
                    await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
                }
            }

            this.logger.LogInformation("PubSub writer daemon stopped.");
        }

        private static bool IsDeleted(JsonElement payload)
        {
            if (payload.TryGetProperty("_deleted", out var deletedProp))
            {
                return deletedProp.ValueKind == JsonValueKind.True;
            }

            return false;
        }

        private static HttpMethod ResolveMethod(string method) =>
            string.IsNullOrWhiteSpace(method) ? HttpMethod.Post : new HttpMethod(method.Trim().ToUpperInvariant());

        private static string Fingerprint(string json) =>
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(json)));

        private static string GetValueFromPayload(JsonElement payload, string configuredKey, string[] fallbackKeys)
        {
            if (payload.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            if (!string.IsNullOrEmpty(configuredKey))
            {
                if (payload.TryGetProperty(configuredKey, out var prop))
                {
                    return prop.ToString();
                }

                foreach (var p in payload.EnumerateObject())
                {
                    if (string.Equals(p.Name, configuredKey, StringComparison.OrdinalIgnoreCase))
                    {
                        return p.Value.ToString();
                    }
                }
            }

            foreach (var key in fallbackKeys)
            {
                if (payload.TryGetProperty(key, out var prop))
                {
                    return prop.ToString();
                }

                foreach (var p in payload.EnumerateObject())
                {
                    if (string.Equals(p.Name, key, StringComparison.OrdinalIgnoreCase))
                    {
                        return p.Value.ToString();
                    }
                }
            }

            // Fallback: check inside a nested "payload" property
            if (payload.TryGetProperty("payload", out var innerPayload) && innerPayload.ValueKind == JsonValueKind.Object)
            {
                return GetValueFromPayload(innerPayload, configuredKey, fallbackKeys);
            }

            return null;
        }

        private async Task<SubscriptionResult> ProcessSubscriptionAsync(
            SubscriptionConfig subscription,
            DestinationConfig destination,
            CancellationToken cancellationToken)
        {
            var result = new SubscriptionResult();
            var url = $"{destination.BaseUrl.TrimEnd('/')}/{subscription.Path.TrimStart('/')}";

            this.logger.LogInformation(
                "Pulling up to {MaxMessages} messages from {SubscriptionId} → {Url}",
                subscription.MaxMessages,
                subscription.SubscriptionId,
                url);

            var messages = await this.pubSubService.PullAsync(
                subscription.SubscriptionId,
                subscription.MaxMessages,
                cancellationToken);

            this.logger.LogInformation(
                "Received {Count} message(s) from {SubscriptionId}",
                messages.Count,
                subscription.SubscriptionId);

            if (messages.Count == 0)
            {
                return result;
            }

            var pkKeys = new[] { "id", "Id", "ID", "projectId", "ProjectId", "contactId", "ContactId", "kundenummer", "Kundenummer" };
            var nameKeys = new[] { "name", "Name", "navn", "Navn", "firstName", "lastName", "email" };

            var parsedMessages = messages.Select(message =>
            {
                try
                {
                    var json = Encoding.UTF8.GetString(message.Message.Data.ToByteArray());
                    var payload = JsonSerializer.Deserialize<JsonElement>(json);
                    var pkVal = GetValueFromPayload(payload, subscription.PrimaryKey, pkKeys) ?? "unknown_key";
                    var nameVal = GetValueFromPayload(payload, subscription.NameKey, nameKeys) ?? "unknown_name";
                    return new { Message = message, Payload = payload, PkVal = pkVal, NameVal = nameVal, IsValid = true };
                }
                catch (Exception ex)
                {
                    this.logger.LogError(
                        ex,
                        "Error parsing message {MessageId} from {SubscriptionId}",
                        message.Message.MessageId,
                        subscription.SubscriptionId);
                    return new { Message = message, Payload = default(JsonElement), PkVal = "error", NameVal = "error", IsValid = false };
                }
            }).ToList();

            // Handle invalid/unparseable messages
            foreach (var item in parsedMessages.Where(m => !m.IsValid))
            {
                result.Error++;
            }

            // Group the valid parsed messages by primary key value
            var groups = parsedMessages.Where(m => m.IsValid).GroupBy(m => m.PkVal);

            foreach (var group in groups)
            {
                var pkVal = group.Key;
                var countInBatch = group.Count();
                var nameVal = group.First().NameVal;

                this.logger.LogInformation(
                    "Subscription: {SubPrefix} | Grouped by Primary Key ({PKName}) = '{PKValue}' (Name: '{NameValue}') | Batch Message Count: {BatchCount}",
                    subscription.SubscriptionIdPrefix,
                    subscription.PrimaryKey ?? "Detected",
                    pkVal,
                    nameVal,
                    countInBatch);

                foreach (var item in group)
                {
                    try
                    {
                        if (IsDeleted(item.Payload))
                        {
                            await this.pubSubService.AcknowledgeAsync(
                                subscription.SubscriptionId,
                                new[] { item.Message.AckId },
                                cancellationToken);
                            result.Skipped++;
                            continue;
                        }

                        // Increment running count for this key (pkVal and nameVal)
                        var counterKey = ValueTuple.Create(subscription.SubscriptionIdPrefix, pkVal, nameVal);
                        int totalCount = this.processedCounters.AddOrUpdate(counterKey, 1, (_, old) => old + 1);

                        this.logger.LogInformation(
                            "Processing message {MessageId} for Primary Key '{PKValue}' (Name: '{NameValue}'). Total processed for this key: {TotalCount}",
                            item.Message.Message.MessageId,
                            pkVal,
                            nameVal,
                            totalCount);

                        var shaped = PayloadShaper.Shape(item.Payload, subscription);

                        foreach (var note in shaped.Notes)
                        {
                            this.logger.LogWarning(
                                "{SubscriptionId} key '{PKValue}': {Note}",
                                subscription.SubscriptionId,
                                pkVal,
                                note);
                        }

                        var targetUrl = url;
                        if (!string.IsNullOrEmpty(subscription.IdField))
                        {
                            if (string.IsNullOrEmpty(shaped.IdValue))
                            {
                                // The URL addresses the resource by id, so without it there is
                                // nothing to write to. Not acked: let it redeliver and land in the
                                // dead-letter topic rather than disappear.
                                this.logger.LogError(
                                    "Message {MessageId} from {SubscriptionId} has no '{IdField}' — cannot build the target URL",
                                    item.Message.Message.MessageId,
                                    subscription.SubscriptionId,
                                    subscription.IdField);
                                result.Error++;
                                continue;
                            }

                            targetUrl = $"{url.TrimEnd('/')}/{Uri.EscapeDataString(shaped.IdValue)}";
                        }

                        // A Pub/Sub message can legitimately be the JSON literal `null`, which
                        // Shape returns as a null node. Dereferencing it threw, so the message was
                        // never acked and redelivered until the dead-letter topic caught it. Send it
                        // as the previous writer did and let the destination reject it.
                        var json = shaped.Body?.ToJsonString() ?? "null";
                        var dedupeKey = (subscription.SubscriptionIdPrefix, pkVal);
                        var fingerprint = Fingerprint(json);

                        if (subscription.SuppressUnchangedPayloads &&
                            this.lastSentPayloads.TryGetValue(dedupeKey, out var previous) &&
                            previous == fingerprint)
                        {
                            await this.pubSubService.AcknowledgeAsync(
                                subscription.SubscriptionId,
                                new[] { item.Message.AckId },
                                cancellationToken);
                            result.Skipped++;
                            continue;
                        }

                        bool posted;
                        if (!destination.Enabled)
                        {
                            this.logger.LogInformation(
                                "Destination '{Destination}' is disabled. Message {MessageId} processed but not sent to {Url}.",
                                destination.Name,
                                item.Message.Message.MessageId,
                                targetUrl);
                            posted = true;
                        }
                        else
                        {
                            posted = await this.writerClient.SendAsync(
                                json,
                                ResolveMethod(subscription.Method),
                                destination,
                                targetUrl,
                                cancellationToken);
                        }

                        if (posted && destination.Enabled && subscription.SuppressUnchangedPayloads)
                        {
                            // Only after a real send that actually succeeded. A failed send must stay
                            // retryable, and a disabled destination never saw the payload at all —
                            // recording it there would suppress the first real send after it is
                            // re-enabled. And only when suppression is on: the cache has no eviction,
                            // so populating it for subscriptions that never read it is pure growth.
                            this.lastSentPayloads[dedupeKey] = fingerprint;
                        }

                        if (posted)
                        {
                            await this.pubSubService.AcknowledgeAsync(
                                subscription.SubscriptionId,
                                new[] { item.Message.AckId },
                                cancellationToken);
                            result.Success++;
                        }
                        else
                        {
                            result.Error++;
                        }
                    }
                    catch (Exception ex)
                    {
                        this.logger.LogError(
                            ex,
                            "Error processing message {MessageId} from {SubscriptionId}",
                            item.Message.Message.MessageId,
                            subscription.SubscriptionId);
                        result.Error++;
                    }
                }
            }

            return result;
        }

        private sealed class SubscriptionResult
        {
            public int Success { get; set; }

            public int Skipped { get; set; }

            public int Error { get; set; }
        }
    }
}
