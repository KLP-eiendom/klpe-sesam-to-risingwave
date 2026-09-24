namespace PubSubWriter.Services
{
    using Google.Cloud.PubSub.V1;

    public interface IPubSubService
    {
        Task<IReadOnlyList<ReceivedMessage>> PullAsync(string subscriptionId, int maxMessages, CancellationToken cancellationToken);

        Task AcknowledgeAsync(string subscriptionId, IEnumerable<string> ackIds, CancellationToken cancellationToken);
    }
}
