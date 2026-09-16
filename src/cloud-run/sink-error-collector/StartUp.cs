namespace SinkErrorCollector
{
    using Klpe.SharedCommon.Config;
    using Klpe.SharedCommon.Helpers;
    using Klpe.SharedCommon.Logging;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.DependencyInjection;
    using Microsoft.Extensions.FileProviders;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Hosting.Internal;
    using RisingWavePollerCommon.Settings;
    using SinkErrorCollector.Services;
    using SinkErrorCollector.Settings;

    public class StartUp
    {
        public static IConfigurationRoot Configuration { get; set; }

        public static void Build(IHostEnvironment env = null)
        {
            Configuration = ConfigurationHelper.GetConfiguration(env ?? GetHostingEnvironment());
        }

        public static void ConfigureServices(IServiceCollection services)
        {
            services.UseKlpeApplicationLogging(Configuration);
            services.UseKlpeSharedCommon();

            if (Configuration != null)
            {
                services.AddSingleton<IConfiguration>(Configuration);
                services.Configure<CloudLoggingSettings>(Configuration.GetSection(nameof(CloudLoggingSettings)));
            }

            services.AddSingleton<IRisingWaveErrorReader, RisingWaveErrorReader>();
            services.AddSingleton<ICloudLoggingPublisher, CloudLoggingPublisher>();
            services.AddHostedService<CollectorService>();
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
