namespace PubSubWriter
{
    using System.Net;
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
    using PubSubWriter.Services;
    using PubSubWriter.Settings;
    using SharedAuth.Auth;

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
                services.Configure<WriterSettings>(Configuration.GetSection(nameof(WriterSettings)));
                services.AddSingleton<WriterSettings>(r =>
                {
                    var settings = r.GetRequiredService<IOptions<WriterSettings>>().Value ?? new WriterSettings();

                    if (settings.Destinations != null)
                    {
                        foreach (var dest in settings.Destinations)
                        {
                            var enabledStr = Configuration[$"WriterSettings:Destinations:{dest.Name}:Enabled"]
                                ?? Configuration[$"WriterSettings:Destinations:{dest.Name}__Enabled"]
                                ?? Configuration[$"WriterSettings__Destinations__{dest.Name}__Enabled"]
                                ?? Configuration[$"{dest.Name}:Enabled"]
                                ?? Configuration[$"{dest.Name}__Enabled"];

                            if (!string.IsNullOrWhiteSpace(enabledStr) && bool.TryParse(enabledStr, out var enabled))
                            {
                                dest.Enabled = enabled;
                            }

                            if (dest.Name.Equals("superoffice", StringComparison.OrdinalIgnoreCase))
                            {
                                if (dest.OAuth != null)
                                {
                                    if (string.IsNullOrWhiteSpace(dest.OAuth.ClientId))
                                    {
                                        dest.OAuth.ClientId = Configuration["KdiApiSettings:ClientId"]
                                            ?? Configuration["SuperOfficeAuth:ClientId"];
                                    }
                                    if (string.IsNullOrWhiteSpace(dest.OAuth.ClientSecret))
                                    {
                                        dest.OAuth.ClientSecret = Configuration["KdiApiSettings:ClientSecret"]
                                            ?? Configuration["SuperOfficeAuth:ClientSecret"];
                                    }
                                }
                            }
                            else if (dest.Name.Equals("document", StringComparison.OrdinalIgnoreCase))
                            {
                                if (dest.OAuth != null)
                                {
                                    if (string.IsNullOrWhiteSpace(dest.OAuth.ClientId))
                                    {
                                        dest.OAuth.ClientId = Configuration["DocumentApiAccessInfo:ClientId"];
                                    }
                                    if (string.IsNullOrWhiteSpace(dest.OAuth.ClientSecret))
                                    {
                                        dest.OAuth.ClientSecret = Configuration["DocumentApiAccessInfo:ClientSecret"];
                                    }
                                }
                            }
                            else if (dest.Name.Equals("leko", StringComparison.OrdinalIgnoreCase))
                            {
                                var token = Configuration["SesamAccessInfo:ByggLekoAccessToken"];
                                if (!string.IsNullOrWhiteSpace(token))
                                {
                                    dest.SyncToken = token;
                                }
                            }
                            else if (dest.Name.Equals("dalux", StringComparison.OrdinalIgnoreCase))
                            {
                                // Same Vault key the poller binds — both services read kv/kdi/<env>,
                                // so there is one Dalux API key, not a read one and a write one.
                                if (string.IsNullOrWhiteSpace(dest.ApiKey))
                                {
                                    dest.ApiKey = Configuration["DaluxApiSettings:ApiKey"]
                                        ?? Configuration["DaluxApi:ApiKey"];
                                }
                            }
                        }
                    }

                    var envName = !string.IsNullOrWhiteSpace(settings.Env)
                        ? settings.Env.Trim().ToLowerInvariant()
                        : GetEnvName();

                    if (settings.Subscriptions != null && !string.IsNullOrWhiteSpace(envName))
                    {
                        var suffix = $"-{envName}";
                        foreach (var sub in settings.Subscriptions)
                        {
                            if (sub != null)
                            {
                                var prefix = !string.IsNullOrWhiteSpace(sub.SubscriptionIdPrefix)
                                    ? sub.SubscriptionIdPrefix
                                    : sub.SubscriptionId;

                                if (!string.IsNullOrWhiteSpace(prefix))
                                {
                                    sub.SubscriptionId = prefix.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)
                                        ? prefix
                                        : $"{prefix}{suffix}";
                                }
                            }
                        }
                    }

                    return settings;
                });
                services.Configure<AuthSettings>(Configuration.GetSection("Authentication"));
            }

            services.AddHttpClient<IWriterClient, WriterClient>()
                .AddPolicyHandler(GetRetryPolicy());

            services.AddSingleton<IPubSubService, PubSubService>();
            services.AddHostedService<WriterService>();
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

        private static string GetEnvName()
        {
            var env = Environment.GetEnvironmentVariable("env")
                      ?? Environment.GetEnvironmentVariable("ENV")
                      ?? Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT");

            if (string.IsNullOrWhiteSpace(env))
            {
                return "dev";
            }

            env = env.Trim().ToLowerInvariant();

            return env switch
            {
                "development" => "dev",
                "production" => "prod",
                _ => env
            };
        }

        private static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
        {
            return HttpPolicyExtensions
                .HandleTransientHttpError()
                // 429 is a refusal, not a partial write — Dalux answers it as E42901 under load —
                // so retrying it is safe in a way retrying an ambiguous 5xx is not.
                .OrResult(response => response.StatusCode == HttpStatusCode.TooManyRequests)
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
