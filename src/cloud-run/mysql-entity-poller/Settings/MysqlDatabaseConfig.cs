namespace MysqlEntityPoller.Settings
{
    public class MysqlDatabaseConfig
    {
        public string Host { get; set; } = string.Empty;

        public int Port { get; set; } = 3306;

        public string DatabaseName { get; set; } = string.Empty;

        public List<TablePollConfig> Tables { get; set; } = new();
    }
}
