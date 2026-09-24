namespace EiendomEntityPoller
{
    using EiendomEntityPoller.Services;
    using EiendomEntityPoller.Settings;
    using Klpe.SharedCommon.Config;
    using Klpe.SharedCommon.Helpers;
    using Klpe.SharedCommon.Logging;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.DependencyInjection;
    using Microsoft.Extensions.FileProviders;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Hosting.Internal;
    using Microsoft.Extensions.Options;
    using Polly;
    using Polly.Extensions.Http;
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
                services.Configure<EiendomApiSettings>(Configuration.GetSection(nameof(EiendomApiSettings)));
                services.AddSingleton<EiendomApiSettings>(r => r.GetService<IOptions<EiendomApiSettings>>().Value);
                services.AddSingleton<IOAuthApiSettings>(r => r.GetRequiredService<EiendomApiSettings>());
                services.Configure<RisingWaveSettings>(Configuration.GetSection(nameof(RisingWaveSettings)));
            }

            services.AddHttpClient<IOAuthTokenService, OAuthTokenService>();
            services.AddHttpClient<IEiendomApiClient, EiendomApiClient>()
                .AddPolicyHandler(GetRetryPolicy());

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

        private static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
        {
            return HttpPolicyExtensions
                .HandleTransientHttpError()
                .WaitAndRetryAsync(
                    retryCount: 3,
                    sleepDurationProvider: retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
                    onRetry: (outcome, timespan, retryCount, context) =>
                    {
                        Console.WriteLine($"Retry {retryCount} after {timespan.TotalSeconds}s due to: {outcome.Exception?.Message ?? outcome.Result.StatusCode.ToString()}");
                    });
        }
    }
}
