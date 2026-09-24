using System.Reflection;
using System.Text.Json;
using Klpe.SharedCommon.Config;
using Klpe.SharedCommon.Errors;
using Klpe.SharedCommon.HealthCheck;
using Microsoft.AspNetCore.Authorization;
using Npgsql;
using RisingWaveDataApi.Authorization;
using RisingWaveDataApi.Repositories;
using RisingWaveDataApi.Services;
using SharedAuth.Extensions;
using Swagger.Config;
using Swagger.Extensions;

internal class Program
{
    private static void Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);

        // Hent konfigurasjon fra Vault
        var vaultConfig = ConfigurationHelper.GetConfiguration(builder.Environment);
        builder.Configuration.AddConfiguration(vaultConfig);

        // Sørg for at swagger_settings.json er lastet
        builder.Configuration.AddJsonFile("swagger_settings.json", optional: true, reloadOnChange: true)
                             .AddJsonFile($"swagger_settings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true);

        SwaggerConfig swaggerConfig = new SwaggerConfig(builder.Configuration, Assembly.GetExecutingAssembly());

        // Configure Controllers
        var mvcBuilder = builder.Services.AddControllers();
        mvcBuilder.AddNewtonsoftJson();
        mvcBuilder.AddGlobalExceptionFilter();
        mvcBuilder.AddJsonOptions(options =>
        {
            options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        });

        // Register Repositories
        builder.Services.AddScoped<ILekoRepository, LekoRepository>();
        builder.Services.AddScoped<IIntegrationOverviewRepository, IntegrationOverviewRepository>();

        // Register Services
        builder.Services.AddSingleton<IMermaidGeneratorService, MermaidGeneratorService>();

        // Configure Swagger/OpenAPI
        builder.Services.AddEndpointsApiExplorer();
        builder.Services.AddHealthChecks();
        builder.Services.AddSwaggerService(swaggerConfig);
        builder.Services.AddExceptionFilter(vaultConfig);

        // Configure Authentication and Authorization
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddKlpeAuthentication(vaultConfig);
        builder.Services.AddAuthorization(options =>
        {
            options.AddPolicy(LekoOrAdminHandler.PolicyName, policy =>
                policy.Requirements.Add(new LekoOrAdminRequirement()));
        });
        builder.Services.AddSingleton<IAuthorizationHandler, LekoOrAdminHandler>();

        // Configure PostgreSQL / RisingWave connection
        var connectionString = builder.Configuration.GetConnectionString("RisingWave");
        if (!string.IsNullOrEmpty(connectionString))
        {
            var dataSourceBuilder = new NpgsqlDataSourceBuilder(connectionString);
            var dataSource = dataSourceBuilder.Build();
            builder.Services.AddSingleton(dataSource);
        }

        var app = builder.Build();

        // Enable Swagger
        app.UseSwagger();
        app.UseSwaggerUi(swaggerConfig.DocUrl, swaggerConfig.Description);
        app.UseKlpeApplicationHealthChecks();

        app.UseHttpsRedirection();

        // Use Authentication and Authorization
        app.UseAuthentication();
        app.UseAuthorization();

        app.MapControllers();

        app.Run();
    }
}