namespace FdvwebEntityPoller.Settings
{
    using RisingWavePollerCommon.Services;

    public class EntityPollConfig : IRisingWaveTableConfig
    {
        /// <summary>
        /// Gets or sets the API path relative to the FDV-web base URL, e.g. "GetBygg".
        /// The full URL becomes {BaseUrl}/{EntityPath}.
        /// </summary>
        public string EntityPath { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the destination table name in RisingWave.
        /// Defaults to the last segment of EntityPath when left empty.
        /// </summary>
        public string TargetTable { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets columns that form the PRIMARY KEY in RisingWave.
        /// Ignored when <see cref="IdExpression"/> is set; the computed <c>_id</c> column is used instead.
        /// </summary>
        public List<string> PrimaryKeyColumns { get; set; } = new();

        /// <summary>
        /// Gets or sets an optional Sesam DTL-style expression used to compute a synthetic <c>_id</c>
        /// column for each row. When set, <c>_id</c> is added to every row and used as the sole
        /// primary key in RisingWave, overriding <see cref="PrimaryKeyColumns"/>.
        /// Supported functions: coalesce, concat, lower, upper, string, date.
        /// Example: <c>concat(byggNavnId, "-", bildearkivTekst)</c>
        /// </summary>
        public string IdExpression { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets overrides RisingWaveSettings.BatchSize for this entity only.
        /// Null means use the global default.
        /// </summary>
        public int? BatchSize { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether to delete rows from RisingWave whose primary key
        /// no longer appears in the API response after each poll.
        /// Only enable when the full dataset is always fetched (no server-side filtering).
        /// Skipped automatically when the response exceeds 100 000 rows.
        /// </summary>
        public bool EnableReconciliation { get; set; }

        public string ResolvedTargetTable =>
            string.IsNullOrWhiteSpace(TargetTable)
                ? EntityPath.Split('/').Last()
                : TargetTable;

        public IReadOnlyList<string> EffectivePrimaryKeyColumns =>
            string.IsNullOrWhiteSpace(IdExpression)
                ? PrimaryKeyColumns
                : new[] { "_id" };
    }
}
