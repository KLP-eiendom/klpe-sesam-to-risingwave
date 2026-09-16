namespace RisingWavePollerCommon.Settings
{
    public class RisingWaveSettings
    {
        public string SqlHost { get; set; } = "localhost";

        public int SqlPort { get; set; } = 4566;

        public string SqlUsername { get; set; } = "root";

        public string SqlPassword { get; set; } = string.Empty;

        public string Database { get; set; } = "dev";

        public string Schema { get; set; } = "public";

        public int BatchSize { get; set; } = 500;

        public bool SslEnabled { get; set; } = false;

        public string ConnectionString =>
            $"Host={SqlHost};Port={SqlPort};Database={Database};Username={SqlUsername};Password={SqlPassword};SSL Mode={(SslEnabled ? "Require" : "Disable")};";
    }
}
