namespace BigQueryEntityPoller
{
    using BigQueryEntityPoller.Services;
    using BigQueryEntityPoller.Settings;
    using Klpe.SharedCommon.Config;
    using Klpe.SharedCommon.Helpers;
    using Klpe.SharedCommon.Logging;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.DependencyInjection;
    using Microsoft.Extensions.FileProviders;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Hosting.Internal;
    using Microsoft.Extensions.Options;
    using RisingWavePollerCommon.Services;
    using RisingWavePollerCommon.Settings;

    public class StartUp
    {
        public static IConfigurationRoot Configuration { get; set; }

        public static void Build(IHostEnvironment env = null, string[] args = null)
        {
            var config = ConfigurationHelper.GetConfiguration(env ?? GetHostingEnvironment());

            if (args != null && args.Length > 0)
            {
                Configuration = new ConfigurationBuilder()
                    .AddConfiguration(config)
                    .AddCommandLine(args)
                    .Build();
            }
            else
            {
                Configuration = config;
            }
        }

        public static void ConfigureServices(IServiceCollection services)
        {
            services.UseKlpeApplicationLogging(Configuration);
            services.UseKlpeSharedCommon();

            if (Configuration != null)
            {
                services.AddSingleton<IConfiguration>(Configuration);
                services.Configure<BigQuerySettings>(Configuration.GetSection(nameof(BigQuerySettings)));
                services.AddSingleton<BigQuerySettings>(r => r.GetService<IOptions<BigQuerySettings>>().Value);
                services.Configure<GcpCredentialSettings>(Configuration.GetSection(nameof(GcpCredentialSettings)));
                services.Configure<RisingWaveSettings>(Configuration.GetSection(nameof(RisingWaveSettings)));
            }

            services.AddSingleton<IBigQuerySourceService, BigQuerySourceService>();
            services.AddSingleton<IRisingWaveService<IRisingWaveTableConfig>, RisingWaveSqlService>();
            services.AddHostedService<PollerService>();
        }

        internal static IHostEnvironment GetHostingEnvironment()
        {
            return new HostingEnvironment
            {
                EnvironmentName = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Development",
                ApplicationName = AppDomain.CurrentDomain.FriendlyName,
                ContentRootPath = AppDomain.CurrentDomain.BaseDirectory,
                ContentRootFileProvider = new PhysicalFileProvider(AppDomain.CurrentDomain.BaseDirectory),
            };
        }
    }
}
