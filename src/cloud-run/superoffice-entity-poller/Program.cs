using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SuperOfficeEntityPoller;

StartUp.Build();

IHost host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((hostContext, services) =>
    {
        hostContext.HostingEnvironment = StartUp.GetHostingEnvironment();
        hostContext.Configuration = StartUp.Configuration;
        StartUp.ConfigureServices(services);
    })
    .Build();

try
{
    await host.RunAsync();
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine("Application Failed {0} {1}", ex.Message, ex.StackTrace);
    return 1;
}