using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Dapper;
using Microsoft.Extensions.Logging;
using Npgsql;
using RisingWaveDataApi.Models;

namespace RisingWaveDataApi.Repositories
{
    public class IntegrationOverviewRepository : IIntegrationOverviewRepository
    {
        private readonly NpgsqlDataSource dataSource;
        private readonly ILogger<IntegrationOverviewRepository> logger;

        public IntegrationOverviewRepository(NpgsqlDataSource dataSource, ILogger<IntegrationOverviewRepository> logger)
        {
            this.dataSource = dataSource;
            this.logger = logger;
        }

        public async Task<List<SystemIntegration>> GetIntegrationOverviewAsync()
        {
            var systems = new Dictionary<string, SystemIntegration>();

            SystemIntegration GetOrCreate(string name)
            {
                if (!systems.TryGetValue(name, out var sys))
                {
                    sys = new SystemIntegration { SystemName = name };
                    systems[name] = sys;
                }

                return sys;
            }

            await using var conn = await this.dataSource.OpenConnectionAsync();

            var tableNames = (await conn.QueryAsync<string>(
                "SELECT name FROM rw_catalog.rw_tables WHERE name LIKE 'stg_%'")).ToList();
            foreach (var name in tableNames)
            {
                ProcessInput(name, GetOrCreate);
            }

            this.logger.LogDebug("Processed {Count} staging tables.", tableNames.Count);

            var sourceNames = await conn.QueryAsync<string>(
                "SELECT name FROM rw_catalog.rw_sources WHERE name LIKE 'src_%'");
            foreach (var name in sourceNames)
            {
                ProcessInput(name, GetOrCreate);
            }

            var sinks = (await conn.QueryAsync(
                "SELECT name, connector FROM rw_catalog.rw_sinks WHERE name LIKE 'snk_%'")).ToList();
            foreach (var sink in sinks)
            {
                ProcessOutput((string)sink.name, (string)sink.connector, GetOrCreate);
            }

            this.logger.LogDebug("Processed {Count} sinks.", sinks.Count);

            foreach (var sys in systems.Values)
            {
                sys.IngestionMethods = sys.IngestionMethods.Distinct().ToList();
                sys.ExportMethods = sys.ExportMethods.Distinct().ToList();

                if (sys.InCount > 0 && sys.OutCount > 0)
                {
                    sys.FlowDirection = "Bidirectional";
                }
                else if (sys.InCount > 0)
                {
                    sys.FlowDirection = "In Only";
                }
                else if (sys.OutCount > 0)
                {
                    sys.FlowDirection = "Out Only";
                }
            }

            var dataApi = GetOrCreate("API Clients (Data API)");
            dataApi.OutCount = 1;
            dataApi.FlowDirection = "Out Only";
            dataApi.ExportMethods.Add("RisingWave Data API");

            return systems.Values.OrderBy(x => x.SystemName).ToList();
        }

        private void ProcessInput(string name, System.Func<string, SystemIntegration> getOrCreate)
        {
            if (name.StartsWith("stg_d365_"))
            {
                AddInput(getOrCreate("Dynamics 365"), "BigQuery Poller");
            }
            else if (name.StartsWith("stg_energinet_"))
            {
                AddInput(getOrCreate("Energinet"), "BigQuery Poller");
            }
            else if (name.StartsWith("stg_eiendom_"))
            {
                AddInput(getOrCreate("Eiendom API"), "REST Poller");
            }
            else if (name.StartsWith("stg_fdvweb_"))
            {
                AddInput(getOrCreate("FDV-web"), "REST Poller");
            }
            else if (name.StartsWith("stg_superoffice_"))
            {
                AddInput(getOrCreate("SuperOffice"), "REST Poller / Webhooks");
            }
            else if (name.StartsWith("stg_leko_") || name == "leko-kontrakt" || name == "lekoworker-directlink")
            {
                AddInput(getOrCreate("Leko"), "Webhooks");
            }
            else if (name.StartsWith("stg_verified_") || name == "verified-envelope")
            {
                AddInput(getOrCreate("Verified"), "Webhooks");
            }
            else if (name.StartsWith("stg_bisnode_") || name.StartsWith("bisnode-"))
            {
                AddInput(getOrCreate("Bisnode"), "Webhooks");
            }
            else if (name.StartsWith("src_forvalter_cdc"))
            {
                AddInput(getOrCreate("Forvalter"), "MySQL CDC");
            }
            else if (name.StartsWith("src_kundeportal_cdc"))
            {
                AddInput(getOrCreate("Kundeportal"), "MySQL CDC");
            }
            else if (name.StartsWith("src_camunda_cdc"))
            {
                AddInput(getOrCreate("Camunda"), "PostgreSQL CDC");
            }
        }

        private void ProcessOutput(string name, string connector, System.Func<string, SystemIntegration> getOrCreate)
        {
            if (name.EndsWith("_forvalter"))
            {
                AddOutput(getOrCreate("Forvalter"), connector);
            }
            else if (name.EndsWith("_kundeportal"))
            {
                AddOutput(getOrCreate("Kundeportal"), connector);
            }
            else if (name.EndsWith("_superoffice"))
            {
                AddOutput(getOrCreate("SuperOffice"), connector);
            }
            else if (name.EndsWith("_leko") || name.Contains("_leko_"))
            {
                AddOutput(getOrCreate("Leko"), connector);
            }
            else if (name.EndsWith("_bq") || name.EndsWith("_bqeos"))
            {
                AddOutput(getOrCreate("BigQuery (kdi_datahub)"), connector);
            }
            else if (name.EndsWith("_powerapp"))
            {
                AddOutput(getOrCreate("PowerApp"), connector);
            }
            else if (name.EndsWith("_findable"))
            {
                AddOutput(getOrCreate("KlpeFindable"), connector);
            }
            else
            {
                this.logger.LogWarning("Ukjent output-system for sink '{SinkName}' (connector: {Connector}).", name, connector);
            }
        }

        private void AddInput(SystemIntegration sys, string method)
        {
            sys.InCount++;
            sys.IngestionMethods.Add(method);
        }

        private void AddOutput(SystemIntegration sys, string method)
        {
            sys.OutCount++;
            sys.ExportMethods.Add(method);
        }
    }
}
