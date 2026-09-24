namespace PubSubWriter.Settings
{
    public class SubscriptionConfig
    {
        public string SubscriptionIdPrefix { get; set; }

        public string SubscriptionId { get; set; }

        /// <summary>Gets or sets the destination name — must match a <see cref="DestinationConfig.Name"/>.</summary>
        public string Destination { get; set; }

        /// <summary>Gets or sets the path appended to <see cref="DestinationConfig.BaseUrl"/>.</summary>
        public string Path { get; set; }

        public int MaxMessages { get; set; } = 100;

        public string PrimaryKey { get; set; }

        public string NameKey { get; set; }

        /// <summary>Gets or sets the HTTP method used for the write. Defaults to POST.</summary>
        public string Method { get; set; } = "POST";

        /// <summary>
        /// Gets or sets the message field whose value is appended to the URL, for APIs that
        /// address the resource in the path (e.g. <c>PATCH /2.1/companies/{companyId}</c>).
        /// Leave null to post to <see cref="Path"/> unchanged.
        /// </summary>
        public string IdField { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether <see cref="IdField"/> is removed from the body
        /// after being used for the URL. Set when the destination rejects or ignores it in the body.
        /// </summary>
        public bool ExcludeIdFieldFromBody { get; set; }

        /// <summary>
        /// Gets or sets a property name to wrap the body in, so the request becomes
        /// <c>{"&lt;name&gt;": { …the message… }}</c>. Leave null to send the message as the body.
        /// </summary>
        public string WrapInProperty { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether null-valued properties are removed from the body
        /// before sending. Needed by destinations that treat an explicit null as "clear this field":
        /// a sink serialises every empty column as null, which would blank out data the destination
        /// owns.
        /// </summary>
        public bool StripNullProperties { get; set; }

        /// <summary>
        /// Gets or sets nested objects to assemble from flat message fields, as
        /// <c>{ "&lt;target property&gt;": { "&lt;sub-property&gt;": "&lt;message field&gt;" } }</c>.
        /// The source fields are consumed — they do not remain at the root of the body.
        /// Sinks can only emit flat scalars, so any nesting the destination requires is built here.
        /// </summary>
        public Dictionary<string, Dictionary<string, string>> NestedObjects { get; set; } = new();

        /// <summary>
        /// Gets or sets the mapping of message fields onto a destination's user-defined-field
        /// envelope. Null when the destination has no such concept.
        /// </summary>
        public UserDefinedFieldConfig UserDefinedFields { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether a message whose shaped body is byte-identical to
        /// the last one sent for the same primary key is skipped.
        ///
        /// OFF by default, and that default is deliberate for any destination we treat as a slave:
        /// pollers upsert every row each run, so the same payload arrives again on a schedule — and
        /// re-sending it is exactly what pulls a record edited in the destination back to what the
        /// master says. Suppressing it saves calls but lets a manual edit there survive until our
        /// own data happens to change. Turn it on only when call volume is the bigger problem.
        /// The cache is in-memory, so a restart lets one full round through either way.
        /// </summary>
        public bool SuppressUnchangedPayloads { get; set; }
    }
}
