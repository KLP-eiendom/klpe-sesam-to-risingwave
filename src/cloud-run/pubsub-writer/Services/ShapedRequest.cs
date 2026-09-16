namespace PubSubWriter.Services
{
    using System.Text.Json.Nodes;

    /// <summary>One Pub/Sub message, reshaped into what the destination expects.</summary>
    public sealed class ShapedRequest
    {
        public ShapedRequest(string idValue, JsonNode body, IReadOnlyList<string> notes)
        {
            this.IdValue = idValue;
            this.Body = body;
            this.Notes = notes;
        }

        /// <summary>
        /// Gets the value to append to the URL, from the subscription's IdField.
        /// Null when the subscription addresses the resource by path alone.
        /// </summary>
        public string IdValue { get; }

        /// <summary>Gets the request body.</summary>
        public JsonNode Body { get; }

        /// <summary>
        /// Gets anything the caller should log about this message — a mapped field the destination
        /// record turned out not to have, and similar. Never a reason to fail the send.
        /// </summary>
        public IReadOnlyList<string> Notes { get; }
    }
}
