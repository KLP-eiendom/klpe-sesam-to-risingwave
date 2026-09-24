namespace PubSubWriter.Services
{
    using Google.Apis.Auth.OAuth2;
    using Google.Cloud.PubSub.V1;
    using Grpc.Auth;
    using Microsoft.Extensions.Logging;
    using PubSubWriter.Settings;

    public class PubSubService : IPubSubService
    {
        private readonly SubscriberServiceApiClient client;
        private readonly string projectId;
        private readonly ILogger<PubSubService> logger;

        public PubSubService(WriterSettings settings, ILogger<PubSubService> logger)
        {
            this.logger = logger;
            this.projectId = settings.ProjectId;

            var credential = string.IsNullOrWhiteSpace(settings.CredentialsJson)
                ? GoogleCredential.GetApplicationDefault()
                : CredentialFactory.FromJson<ServiceAccountCredential>(settings.CredentialsJson).ToGoogleCredential();

            var channelCredential = credential.ToChannelCredentials();
            this.client = new SubscriberServiceApiClientBuilder
            {
                ChannelCredentials = channelCredential,
            }.Build();
        }

        public async Task<IReadOnlyList<ReceivedMessage>> PullAsync(string subscriptionId, int maxMessages, CancellationToken cancellationToken)
        {
            var subscriptionName = SubscriptionName.FromProjectSubscription(this.projectId, subscriptionId);
            var response = await this.client.PullAsync(subscriptionName, maxMessages, cancellationToken);
            return response.ReceivedMessages;
        }

        public async Task AcknowledgeAsync(string subscriptionId, IEnumerable<string> ackIds, CancellationToken cancellationToken)
        {
            var subscriptionName = SubscriptionName.FromProjectSubscription(this.projectId, subscriptionId);
            await this.client.AcknowledgeAsync(subscriptionName, ackIds, cancellationToken);
        }
    }
}
