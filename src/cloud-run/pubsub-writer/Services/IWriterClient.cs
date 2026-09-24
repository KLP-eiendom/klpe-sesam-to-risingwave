namespace PubSubWriter.Services
{
    using PubSubWriter.Settings;

    public interface IWriterClient
    {
        /// <summary>Sends one already-shaped request body to a destination.</summary>
        /// <param name="json">The serialised request body.</param>
        /// <param name="method">The HTTP method the destination expects (POST, PATCH, …).</param>
        /// <param name="destination">Destination config, carrying auth.</param>
        /// <param name="url">The full target URL.</param>
        /// <param name="cancellationToken">Token that aborts the request.</param>
        /// <returns>True when the destination accepted the write.</returns>
        Task<bool> SendAsync(
            string json,
            HttpMethod method,
            DestinationConfig destination,
            string url,
            CancellationToken cancellationToken);
    }
}
