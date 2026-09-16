using System.Net;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RisingWaveDataApi.Repositories;
using RisingWaveDataApi.Services;

namespace RisingWaveDataApi.Controllers
{
    [ApiController]
    [Route("api/v1/[controller]")]
    [Authorize]
    public class OverviewController : ControllerBase
    {
        private readonly IIntegrationOverviewRepository repository;
        private readonly IMermaidGeneratorService mermaidService;
        private readonly ILogger<OverviewController> logger;

        public OverviewController(
            IIntegrationOverviewRepository repository,
            IMermaidGeneratorService mermaidService,
            ILogger<OverviewController> logger)
        {
            this.repository = repository;
            this.mermaidService = mermaidService;
            this.logger = logger;
        }

        [HttpGet]
        public async Task<IActionResult> GetOverview()
        {
            try
            {
                var overview = await this.repository.GetIntegrationOverviewAsync();
                return Ok(overview);
            }
            catch (Exception ex)
            {
                this.logger.LogError(ex, "Feil ved henting av integrasjonsoversikt.");
                return StatusCode(500, new { error = "En intern feil oppstod." });
            }
        }

        [HttpGet("mermaid")]
        public async Task<IActionResult> GetMermaid()
        {
            try
            {
                var overview = await this.repository.GetIntegrationOverviewAsync();
                var mermaid = this.mermaidService.GenerateFlowchart(overview);
                return Content(mermaid, "text/plain");
            }
            catch (Exception ex)
            {
                this.logger.LogError(ex, "Feil ved generering av Mermaid-diagram.");
                return StatusCode(500, new { error = "En intern feil oppstod." });
            }
        }

        [AllowAnonymous]
        [HttpGet("render")]
        public async Task<IActionResult> RenderMermaid()
        {
            var overview = await this.repository.GetIntegrationOverviewAsync();
            var mermaid = this.mermaidService.GenerateFlowchart(overview);
            var mermaidEncoded = WebUtility.HtmlEncode(mermaid);

            var html = $@"
<!DOCTYPE html>
<html lang=""en"">
<head>
    <meta charset=""UTF-8"">
    <meta name=""viewport"" content=""width=device-width, initial-scale=1.0"">
    <title>RisingWave Datahub Overview</title>
    <style>
        body {{ font-family: sans-serif; background-color: #f8f9fa; margin: 0; padding: 20px; }}
        h1 {{ text-align: center; color: #333; }}
        .mermaid {{ display: flex; justify-content: center; margin-top: 40px; }}
    </style>
</head>
<body>
    <h1>RisingWave Datahub Integrations</h1>
    <div class=""mermaid"">
{mermaidEncoded}
    </div>
    <script type=""module"">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10.9.3/dist/mermaid.esm.min.mjs';
        mermaid.initialize({{ startOnLoad: true }});
    </script>
</body>
</html>";

            return Content(html, "text/html");
        }
    }
}
