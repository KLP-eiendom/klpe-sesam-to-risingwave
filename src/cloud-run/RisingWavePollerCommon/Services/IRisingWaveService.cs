namespace RisingWavePollerCommon.Services
{
    using RisingWavePollerCommon.Models;

    public interface IRisingWaveService<TPollConfig>
    {
        Task<PublishResult> PublishRowsAsync(
            IReadOnlyList<IReadOnlyDictionary<string, object>> rows,
            TPollConfig tableConfig,
            int batchSize,
            CancellationToken cancellationToken = default);

        /// <summary>
        /// Deletes rows from the RisingWave staging table whose primary key is no longer present
        /// in <paramref name="currentRows"/>. Only supported for tables with a single primary key column.
        /// Call this after <see cref="PublishRowsAsync"/> when a full dataset has been fetched.
        /// </summary>
        /// <returns>The number of stale rows deleted.</returns>
        Task<int> ReconcileAsync(
            IReadOnlyList<IReadOnlyDictionary<string, object>> currentRows,
            TPollConfig tableConfig,
            CancellationToken cancellationToken = default);
    }
}
