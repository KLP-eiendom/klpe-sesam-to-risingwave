namespace MysqlEntityPoller.Settings
{
    public class MysqlPollerSettings
    {
        public string Username { get; set; } = string.Empty;

        public string Password { get; set; } = string.Empty;

        public List<MysqlDatabaseConfig> Databases { get; set; } = new();
    }
}
