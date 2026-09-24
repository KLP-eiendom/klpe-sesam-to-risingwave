namespace FdvwebEntityPoller
{
    using FdvwebEntityPoller.Services;
    using FdvwebEntityPoller.Settings;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using RisingWavePollerCommon.Models;
    using RisingWavePollerCommon.Services;
    using RisingWavePollerCommon.Settings;

    public class PollerService : BackgroundService
    {
        private readonly ILogger<PollerService> logger;
        private readonly IFdvwebApiClient apiClient;
        private readonly IRisingWaveService<IRisingWaveTableConfig> risingWaveService;
        private readonly FdvwebApiSettings apiSettings;
        private readonly RisingWaveSettings rwSettings;
        private readonly IHostApplicationLifetime lifetime;

        public PollerService(
            ILogger<PollerService> logger,
            IFdvwebApiClient apiClient,
            IRisingWaveService<IRisingWaveTableConfig> risingWaveService,
            FdvwebApiSettings apiSettings,
            IOptions<RisingWaveSettings> rwSettings,
            IHostApplicationLifetime lifetime)
        {
            this.logger = logger;
            this.apiClient = apiClient;
            this.risingWaveService = risingWaveService;
            this.apiSettings = apiSettings;
            this.rwSettings = rwSettings.Value;
            this.lifetime = lifetime;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            var overall = new PublishResult();

            try
            {
                var entities = this.apiSettings.Entities;

                this.logger.LogInformation(
                    "Starting FDV-web entity poller — {Count} entity type(s) configured",
                    entities.Count);

                foreach (var entity in entities)
                {
                    try
                    {
                        var rows = await this.apiClient.FetchEntitiesAsync(entity, stoppingToken);
                        var batchSize = entity.BatchSize ?? this.rwSettings.BatchSize;
                        var result = await this.risingWaveService.PublishRowsAsync(rows, entity, batchSize, stoppingToken);
                        overall.SuccessCount += result.SuccessCount;
                        overall.ErrorCount += result.ErrorCount;

                        if (entity.EnableReconciliation)
                        {
                            overall.DeletedCount += await this.risingWaveService.ReconcileAsync(rows, entity, stoppingToken);
                        }
                    }
                    catch (Exception ex)
                    {
                        this.logger.LogError(ex, "Failed to poll entity {EntityPath}", entity.EntityPath);
                        overall.ErrorCount++;
                    }
                }

                this.logger.LogInformation(
                    "Poller completed: {SuccessCount} rows published, {DeletedCount} rows reconciled, {ErrorCount} errors",
                    overall.SuccessCount,
                    overall.DeletedCount,
                    overall.ErrorCount);

                Environment.ExitCode = overall.ErrorCount > 0 ? 1 : 0;
            }
            catch (Exception ex)
            {
                this.logger.LogError(ex, "Poller failed with unhandled exception");
                Environment.ExitCode = 1;
                throw;
            }
            finally
            {
                this.lifetime.StopApplication();
            }
        }
    }
}
