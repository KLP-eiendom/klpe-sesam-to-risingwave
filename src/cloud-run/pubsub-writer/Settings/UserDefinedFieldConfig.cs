namespace PubSubWriter.Settings
{
    /// <summary>
    /// Maps message fields onto a destination's user-defined-field envelope.
    ///
    /// The envelope shape is Dalux FM's — <c>{"items":[{"name":…,"values":[{"text":…}]}]}</c>.
    /// Every item the destination returned is echoed back, each reduced to <c>name</c> +
    /// <c>values</c>, with only the mapped values replaced.
    ///
    /// Both halves of that are deliberate. Reducing to name + values is the shape verified
    /// against the live API, and it drops <c>userDefinedFieldId</c> and <c>description</c>,
    /// which the spec documents as ignored on write but which were never confirmed to be
    /// tolerated. Echoing every item — not just the mapped ones — is because omitting a field
    /// might clear it, and the API has no delete to undo that with.
    /// </summary>
    public class UserDefinedFieldConfig
    {
        /// <summary>
        /// Gets or sets the message field holding the destination's CURRENT envelope. A sink can
        /// only carry it as a JSON string, so both a string and an object are accepted.
        /// </summary>
        public string SourceField { get; set; }

        /// <summary>
        /// Gets or sets the fields to write, as
        /// <c>{ "&lt;user-defined field name&gt;": "&lt;message field&gt;" }</c>.
        /// Matching is on the field's NAME, not its id: ids are per-environment (Dalux hands out
        /// 1294–1297 in one environment and different numbers in the next), names are stable.
        /// The message fields are consumed — they do not remain at the root of the body.
        /// </summary>
        public Dictionary<string, string> Map { get; set; } = new();
    }
}
