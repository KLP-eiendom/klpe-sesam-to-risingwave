namespace MysqlEntityPoller.Services
{
    using MysqlEntityPoller.Settings;

    public interface IMysqlTableReader
    {
        Task<IReadOnlyList<IReadOnlyDictionary<string, object>>> ReadTableAsync(
            string host,
            int port,
            string database,
            string username,
            string password,
            TablePollConfig tableConfig,
            CancellationToken cancellationToken = default);
    }
}
