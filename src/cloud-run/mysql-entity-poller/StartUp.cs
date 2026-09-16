namespace MysqlEntityPoller
{
    using Klpe.SharedCommon.Config;
    using Klpe.SharedCommon.Helpers;
    using Klpe.SharedCommon.Logging;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.DependencyInjection;
    using Microsoft.Extensions.FileProviders;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Hosting.Internal;
    using Microsoft.Extensions.Options;
    using MysqlEntityPoller.Services;
    using MysqlEntityPoller.Settings;
    using RisingWavePollerCommon.Services;
    using RisingWavePollerCommon.Settings;

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
                services.Configure<MysqlPollerSettings>(Configuration.GetSection(nameof(MysqlPollerSettings)));
                services.AddSingleton<MysqlPollerSettings>(r => r.GetService<IOptions<MysqlPollerSettings>>().Value);
                services.Configure<RisingWaveSettings>(Configuration.GetSection(nameof(RisingWaveSettings)));
            }

            services.AddSingleton<IMysqlTableReader, MysqlTableReader>();
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
