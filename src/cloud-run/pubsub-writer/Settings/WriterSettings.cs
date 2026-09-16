namespace PubSubWriter.Settings
{
    public class WriterSettings
    {
        public string ProjectId { get; set; }

        public string CredentialsJson { get; set; }

        public string Env { get; set; }

        public List<DestinationConfig> Destinations { get; set; } = new();

        public List<SubscriptionConfig> Subscriptions { get; set; } = new();
    }
}
