namespace PubSubWriter.Services
{
    using System.Linq;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using PubSubWriter.Settings;

    /// <summary>
    /// Turns a Pub/Sub message into the request a destination expects.
    ///
    /// A RisingWave sink can only emit flat scalar columns, and it serialises every empty column
    /// as an explicit null. Destinations that want nested objects, or that treat a null as "clear
    /// this field", therefore need the message reshaped before it is sent — and this is the only
    /// place that happens. Everything it does is driven by <see cref="SubscriptionConfig"/>; it
    /// knows no destination by name.
    ///
    /// Subscriptions that configure none of it get their message through untouched, which is what
    /// every pre-existing subscription does.
    /// </summary>
    public static class PayloadShaper
    {
        public static ShapedRequest Shape(JsonElement payload, SubscriptionConfig subscription)
        {
            var notes = new List<string>();
            var raw = payload.GetRawText();

            if (JsonNode.Parse(raw) is not JsonObject root)
            {
                // Not an object — nothing to reshape, and nothing that could be addressed by field.
                return new ShapedRequest(null, JsonNode.Parse(raw), notes);
            }

            var idValue = ExtractId(root, subscription);

            foreach (var nested in subscription.NestedObjects)
            {
                BuildNestedObject(root, nested.Key, nested.Value);
            }

            if (subscription.UserDefinedFields != null)
            {
                ApplyUserDefinedFields(root, subscription.UserDefinedFields, notes);
            }

            if (subscription.StripNullProperties)
            {
                StripNulls(root);
            }

            JsonNode body = root;
            if (!string.IsNullOrEmpty(subscription.WrapInProperty))
            {
                body = new JsonObject { [subscription.WrapInProperty] = root };
            }

            return new ShapedRequest(idValue, body, notes);
        }

        /// <summary>
        /// Case-insensitive property lookup, matching how the rest of the writer reads message
        /// fields — RisingWave folds unquoted identifiers to lowercase, so a sink column can reach
        /// us in a different case than the config names it.
        /// </summary>
        private static string FindPropertyName(JsonObject root, string name)
        {
            if (string.IsNullOrEmpty(name))
            {
                return null;
            }

            if (root.ContainsKey(name))
            {
                return name;
            }

            return root.Select(p => p.Key)
                .FirstOrDefault(key => string.Equals(key, name, StringComparison.OrdinalIgnoreCase));
        }

        private static string ExtractId(JsonObject root, SubscriptionConfig subscription)
        {
            var key = FindPropertyName(root, subscription.IdField);
            if (key == null)
            {
                return null;
            }

            var value = root[key]?.ToString();

            if (subscription.ExcludeIdFieldFromBody)
            {
                root.Remove(key);
            }

            return string.IsNullOrWhiteSpace(value) ? null : value;
        }

        private static void BuildNestedObject(JsonObject root, string target, Dictionary<string, string> map)
        {
            var nested = new JsonObject();

            foreach (var entry in map)
            {
                var key = FindPropertyName(root, entry.Value);
                if (key == null)
                {
                    continue;
                }

                var value = root[key]?.DeepClone();
                root.Remove(key);

                // A null sub-property is omitted rather than sent: same "empty means no opinion"
                // rule as StripNullProperties, applied before the object is assembled.
                if (value != null)
                {
                    nested[entry.Key] = value;
                }
            }

            if (nested.Count > 0)
            {
                root[target] = nested;
            }
        }

        private static void ApplyUserDefinedFields(JsonObject root, UserDefinedFieldConfig config, List<string> notes)
        {
            var sourceKey = FindPropertyName(root, config.SourceField);
            var envelope = sourceKey == null ? null : ParseEnvelope(root[sourceKey]);

            if (sourceKey != null)
            {
                root.Remove(sourceKey);
            }

            // Collect the desired values, consuming their message fields either way so they never
            // leak into the body as unknown root properties.
            var desired = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in config.Map)
            {
                var key = FindPropertyName(root, entry.Value);
                if (key == null)
                {
                    continue;
                }

                var value = root[key]?.ToString();
                root.Remove(key);

                if (!string.IsNullOrWhiteSpace(value))
                {
                    desired[entry.Key] = value;
                }
            }

            if (desired.Count == 0)
            {
                return;
            }

            if (envelope?["items"] is not JsonArray items)
            {
                notes.Add(
                    $"destination record has no user-defined fields — {string.Join(", ", desired.Keys)} not written");
                return;
            }

            var written = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var rewritten = new JsonArray();

            foreach (var node in items)
            {
                if (node is not JsonObject item)
                {
                    continue;
                }

                var name = item["name"]?.ToString()?.Trim();

                if (string.IsNullOrEmpty(name))
                {
                    // No name means we cannot address it, and dropping it could clear it.
                    // Pass it through exactly as it arrived.
                    rewritten.Add(item.DeepClone());
                    continue;
                }

                // Reduced to name + values: that is the shape verified against the live API,
                // and it drops userDefinedFieldId and description, which the spec documents
                // as ignored on write but which were never confirmed to be tolerated.
                var values = desired.TryGetValue(name, out var value)
                    ? new JsonArray(new JsonObject { ["text"] = value })
                    : item["values"]?.DeepClone();

                if (desired.ContainsKey(name))
                {
                    written.Add(name);
                }

                var rebuilt = new JsonObject { ["name"] = name };
                if (values != null)
                {
                    rebuilt["values"] = values;
                }

                rewritten.Add(rebuilt);
            }

            foreach (var missing in desired.Keys.Where(k => !written.Contains(k)))
            {
                notes.Add($"user-defined field '{missing}' not present on the destination record — not written");
            }

            // Every field the destination returned goes back, including the ones we do not
            // own — omitting one risks clearing it, and that is not something to find out
            // the hard way against an API with no delete.
            envelope["items"] = rewritten;
            root[config.SourceField] = envelope;
        }

        /// <summary>
        /// Reads the envelope whether it arrives as an object or, as a sink can only carry it, as a
        /// JSON string. Returns a detached copy so it can be re-attached after editing.
        /// </summary>
        private static JsonObject ParseEnvelope(JsonNode node)
        {
            if (node == null)
            {
                return null;
            }

            try
            {
                var text = node is JsonValue value && value.TryGetValue<string>(out var s)
                    ? s
                    : node.ToJsonString();

                return string.IsNullOrWhiteSpace(text) ? null : JsonNode.Parse(text) as JsonObject;
            }
            catch (JsonException)
            {
                return null;
            }
        }

        private static void StripNulls(JsonNode node)
        {
            switch (node)
            {
                case JsonObject obj:
                    foreach (var key in obj.Where(p => p.Value is null).Select(p => p.Key).ToList())
                    {
                        obj.Remove(key);
                    }

                    foreach (var child in obj.Select(p => p.Value).ToList())
                    {
                        StripNulls(child);
                    }

                    break;

                case JsonArray array:
                    // Array entries keep their positions — removing one would shift the rest, and
                    // for a user-defined-field array that would silently retarget every entry.
                    foreach (var child in array.ToList())
                    {
                        StripNulls(child);
                    }

                    break;
            }
        }
    }
}
