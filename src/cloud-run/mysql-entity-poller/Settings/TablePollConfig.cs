namespace MysqlEntityPoller.Settings
{
    using RisingWavePollerCommon.Services;

    public class TablePollConfig : IRisingWaveTableConfig
    {
        public string TableName { get; set; } = string.Empty;

        public string TargetTable { get; set; } = string.Empty;

        public string IdExpression { get; set; } = string.Empty;

        public List<string> PrimaryKeyColumns { get; set; } = new();

        public int? BatchSize { get; set; }

        public bool EnableReconciliation { get; set; }

        public string ResolvedTargetTable =>
            string.IsNullOrWhiteSpace(TargetTable) ? TableName : TargetTable;

        public IReadOnlyList<string> EffectivePrimaryKeyColumns =>
            string.IsNullOrWhiteSpace(IdExpression)
                ? PrimaryKeyColumns
                : new[] { "_id" };
    }
}
