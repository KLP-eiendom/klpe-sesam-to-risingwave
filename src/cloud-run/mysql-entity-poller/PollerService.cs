namespace MysqlEntityPoller
{
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Options;
    using MysqlEntityPoller.Services;
    using MysqlEntityPoller.Settings;
    using RisingWavePollerCommon.Models;
    using RisingWavePollerCommon.Services;
    using RisingWavePollerCommon.Settings;

    public class PollerService : BackgroundService
    {
        private readonly ILogger<PollerService> logger;
        private readonly IMysqlTableReader tableReader;
        private readonly IRisingWaveService<IRisingWaveTableConfig> risingWaveService;
        private readonly MysqlPollerSettings pollerSettings;
        private readonly RisingWaveSettings rwSettings;
        private readonly IHostApplicationLifetime lifetime;

        public PollerService(
            ILogger<PollerService> logger,
            IMysqlTableReader tableReader,
            IRisingWaveService<IRisingWaveTableConfig> risingWaveService,
            MysqlPollerSettings pollerSettings,
            IOptions<RisingWaveSettings> rwSettings,
            IHostApplicationLifetime lifetime)
        {
            this.logger = logger;
            this.tableReader = tableReader;
            this.risingWaveService = risingWaveService;
            this.pollerSettings = pollerSettings;
            this.rwSettings = rwSettings.Value;
            this.lifetime = lifetime;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            var overall = new PublishResult();

            try
            {
                this.logger.LogInformation(
                    "Starting MySQL entity poller — {DbCount} database(s) configured",
                    this.pollerSettings.Databases.Count);

                foreach (var db in this.pollerSettings.Databases)
                {
                    foreach (var table in db.Tables)
                    {
                        try
                        {
                            var rows = await this.tableReader.ReadTableAsync(
                                db.Host,
                                db.Port,
                                db.DatabaseName,
                                this.pollerSettings.Username,
                                this.pollerSettings.Password,
                                table,
                                stoppingToken);

                            var batchSize = table.BatchSize ?? this.rwSettings.BatchSize;
                            var result = await this.risingWaveService.PublishRowsAsync(rows, table, batchSize, stoppingToken);
                            overall.SuccessCount += result.SuccessCount;
                            overall.ErrorCount += result.ErrorCount;

                            if (table.EnableReconciliation)
                            {
                                overall.DeletedCount += await this.risingWaveService.ReconcileAsync(rows, table, stoppingToken);
                            }
                        }
                        catch (Exception ex)
                        {
                            this.logger.LogError(
                                ex,
                                "Failed to poll table {Table} from {Database}",
                                table.TableName,
                                db.DatabaseName);
                            overall.ErrorCount++;
                        }
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
