namespace BigQueryEntityPoller.Settings
{
    using RisingWavePollerCommon.Services;

    public class TablePollConfig : IRisingWaveTableConfig
    {
        public string DatasetId { get; set; } = string.Empty;

        public string TableId { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets Optional SQL WHERE clause to filter rows, e.g. "updated_at > '2024-01-01'".
        /// Leave empty to fetch the full table.
        /// </summary>
        public string WhereClause { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets Destination table name in RisingWave.
        /// Defaults to TableId when left empty.
        /// </summary>
        public string TargetTable { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets Overrides RisingWaveSettings.BatchSize for this table only.
        /// Null means use the global default.
        /// </summary>
        public int? BatchSize { get; set; }

        /// <summary>
        /// Gets or sets columns that form the PRIMARY KEY in RisingWave.
        /// Required for upsert behaviour — without a primary key, rows are appended on every poll.
        /// Ignored when <see cref="IdExpression"/> is set; the computed <c>_id</c> column is used instead.
        /// </summary>
        public List<string> PrimaryKeyColumns { get; set; } = new();

        /// <summary>
        /// Gets or sets a value indicating whether to delete rows from RisingWave whose primary key
        /// no longer appears in the BigQuery result after each poll.
        /// Only enable when the full table is fetched — do NOT enable when <see cref="WhereClause"/>
        /// is set, as only a subset of rows is returned and all others would be deleted.
        /// Skipped automatically when the response exceeds 100 000 rows.
        /// </summary>
        public bool EnableReconciliation { get; set; }

        /// <summary>
        /// Gets or sets an optional Sesam DTL-style expression used to compute a synthetic <c>_id</c>
        /// column for each row. When set, <c>_id</c> is added to every row and used as the sole
        /// primary key in RisingWave, overriding <see cref="PrimaryKeyColumns"/>.
        /// Supported functions: coalesce, concat, lower, upper, string, date.
        /// Example: <c>coalesce(lower(epost), bruker_id)</c>
        /// </summary>
        public string IdExpression { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets an optional column name that holds an expiry date/timestamp.
        /// When set, the poller adds a computed boolean column <c>_is_active</c> to every row:
        /// <c>true</c> when the column value is NULL or its date is &gt;= today (UTC), <c>false</c> otherwise.
        /// Use this to avoid NOW() filters in RisingWave materialized views, which cause continuous
        /// retraction churn. The MV can then filter on <c>_is_active = true</c> instead.
        /// </summary>
        public string ActiveUntilColumn { get; set; } = string.Empty;

        public string ResolvedTargetTable =>
            string.IsNullOrWhiteSpace(TargetTable) ? TableId : TargetTable;

        /// <summary>
        /// Gets the effective primary key columns to use in RisingWave.
        /// Returns <c>["_id"]</c> when <see cref="IdExpression"/> is configured,
        /// otherwise returns <see cref="PrimaryKeyColumns"/>.
        /// </summary>
        public IReadOnlyList<string> EffectivePrimaryKeyColumns =>
            string.IsNullOrWhiteSpace(IdExpression)
                ? PrimaryKeyColumns
                : new[] { "_id" };
    }
}
