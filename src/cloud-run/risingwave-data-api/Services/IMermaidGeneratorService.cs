using System.Collections.Generic;
using RisingWaveDataApi.Models;

namespace RisingWaveDataApi.Services
{
    public interface IMermaidGeneratorService
    {
        string GenerateFlowchart(List<SystemIntegration> systems);
    }
}
