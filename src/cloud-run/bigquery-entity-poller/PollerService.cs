namespace BigQueryEntityPoller
{
    using BigQueryEntityPoller.Services;
    using BigQueryEntityPoller.Settings;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using RisingWavePollerCommon.Models;
    using RisingWavePollerCommon.Services;
    using RisingWavePollerCommon.Settings;

    public class PollerService : BackgroundService
    {
        private readonly ILogger<PollerService> logger;
        private readonly IBigQuerySourceService sourceService;
        private readonly IRisingWaveService<IRisingWaveTableConfig> risingWaveService;
        private readonly IHostApplicationLifetime lifetime;
        private readonly BigQuerySettings bqSettings;
        private readonly RisingWaveSettings rwSettings;
        private readonly IConfiguration configuration;

        public PollerService(
            ILogger<PollerService> logger,
            IBigQuerySourceService sourceService,
            IRisingWaveService<IRisingWaveTableConfig> risingWaveService,
            IHostApplicationLifetime lifetime,
            IOptions<BigQuerySettings> bqSettings,
            IOptions<RisingWaveSettings> rwSettings,
            IConfiguration configuration)
        {
            this.logger = logger;
            this.sourceService = sourceService;
            this.risingWaveService = risingWaveService;
            this.lifetime = lifetime;
            this.bqSettings = bqSettings.Value;
            this.rwSettings = rwSettings.Value;
            this.configuration = configuration;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            var tables = this.bqSettings.Tables;

            var targetFilter = this.configuration["table"];
            if (!string.IsNullOrWhiteSpace(targetFilter))
            {
                tables = tables
                    .Where(t => t.ResolvedTargetTable.Equals(targetFilter, StringComparison.OrdinalIgnoreCase))
                    .ToList();

                if (tables.Count == 0)
                {
                    this.logger.LogError(
                        "No table matching --table '{Filter}' found in BigQuerySettings.Tables",
                        targetFilter);
                    Environment.ExitCode = 1;
                    this.lifetime.StopApplication();
                    return;
                }

                this.logger.LogInformation("--table filter active: running only '{Filter}'", targetFilter);
            }

            if (tables.Count == 0)
            {
                this.logger.LogWarning("No tables configured in BigQuerySettings.Tables — nothing to poll");
                Environment.ExitCode = 0;
                this.lifetime.StopApplication();
                return;
            }

            this.logger.LogInformation(
                "Starting BigQuery entity poller: project={ProjectId}, {TableCount} table(s), parallelism={Parallelism}",
                this.bqSettings.ProjectId,
                tables.Count,
                this.bqSettings.MaxParallelism);

            using var semaphore = new SemaphoreSlim(this.bqSettings.MaxParallelism);

            var tasks = tables.Select(table => this.PollTableAsync(table, semaphore, stoppingToken));
            var results = await Task.WhenAll(tasks);

            var overall = new PublishResult();
            foreach (var r in results)
            {
                overall.SuccessCount += r.SuccessCount;
                overall.ErrorCount += r.ErrorCount;
            }

            this.logger.LogInformation(
                "All tables complete: {SuccessCount} rows published, {DeletedCount} rows reconciled, {ErrorCount} errors across {TableCount} table(s)",
                overall.SuccessCount,
                overall.DeletedCount,
                overall.ErrorCount,
                tables.Count);

            Environment.ExitCode = overall.ErrorCount > 0 ? 1 : 0;
            this.lifetime.StopApplication();
        }

        private async Task<PublishResult> PollTableAsync(
            TablePollConfig table,
            SemaphoreSlim semaphore,
            CancellationToken cancellationToken)
        {
            await semaphore.WaitAsync(cancellationToken);
            try
            {
                this.logger.LogInformation(
                    "Polling {DatasetId}.{TableId} → {TargetTable}",
                    table.DatasetId,
                    table.TableId,
                    table.ResolvedTargetTable);

                var rows = await this.sourceService.FetchRowsAsync(table, cancellationToken);
                var batchSize = table.BatchSize ?? this.rwSettings.BatchSize;
                var result = await this.risingWaveService.PublishRowsAsync(rows, table, batchSize, cancellationToken);

                if (table.EnableReconciliation)
                {
                    result.DeletedCount = await this.risingWaveService.ReconcileAsync(rows, table, cancellationToken);
                }

                return result;
            }
            catch (Exception ex)
            {
                this.logger.LogError(
                    ex,
                    "Failed to poll {DatasetId}.{TableId}",
                    table.DatasetId,
                    table.TableId);
                return new PublishResult { ErrorCount = 1 };
            }
            finally
            {
                semaphore.Release();
            }
        }
    }
}
