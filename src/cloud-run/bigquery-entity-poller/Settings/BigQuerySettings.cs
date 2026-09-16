namespace BigQueryEntityPoller.Settings
{
    public class BigQuerySettings
    {
        public string ProjectId { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the maximum number of BigQuery tables polled concurrently.
        /// </summary>
        public int MaxParallelism { get; set; } = 4;

        /// <summary>
        /// Gets or sets List of BigQuery tables to poll.
        /// </summary>
        public List<TablePollConfig> Tables { get; set; } = new();
    }
}
