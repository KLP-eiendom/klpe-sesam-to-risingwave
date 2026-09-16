namespace SinkErrorCollector
{
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Logging;
    using SinkErrorCollector.Services;

    public class CollectorService : BackgroundService
    {
        private readonly ILogger<CollectorService> logger;
        private readonly IRisingWaveErrorReader reader;
        private readonly ICloudLoggingPublisher publisher;
        private readonly IHostApplicationLifetime lifetime;

        public CollectorService(
            ILogger<CollectorService> logger,
            IRisingWaveErrorReader reader,
            ICloudLoggingPublisher publisher,
            IHostApplicationLifetime lifetime)
        {
            this.logger = logger;
            this.reader = reader;
            this.publisher = publisher;
            this.lifetime = lifetime;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            this.logger.LogInformation("Starting sink-error-collector daemon...");

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    this.logger.LogDebug("Starting sink-error-collector polling cycle");

                    var events = await this.reader.ReadSinkFailEventsAsync(stoppingToken);

                    if (events.Count > 0)
                    {
                        this.logger.LogInformation("Found {Count} SINK_FAIL events", events.Count);
                        var written = await this.publisher.PublishAsync(events, stoppingToken);
                        this.logger.LogInformation(
                            "Collector cycle completed: {Found} events read, {Written} entries published",
                            events.Count,
                            written);
                    }
                    else
                    {
                        this.logger.LogDebug("No SINK_FAIL events found in this cycle");
                    }
                }
                catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
                {
                    this.logger.LogError(ex, "Collector failed with unhandled exception in cycle");
                }

                if (!stoppingToken.IsCancellationRequested)
                {
                    // Delay for 5 minutes between each check to avoid hammering RisingWave
                    await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
                }
            }

            this.logger.LogInformation("sink-error-collector daemon stopped.");
        }
    }
}
