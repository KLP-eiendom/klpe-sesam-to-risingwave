using System.Collections.Generic;

namespace RisingWaveDataApi.Models
{
    public class SystemIntegration
    {
        public string SystemName { get; set; } = string.Empty;

        public string FlowDirection { get; set; } = string.Empty;

        public int InCount { get; set; }

        public int OutCount { get; set; }

        public List<string> IngestionMethods { get; set; } = new();

        public List<string> ExportMethods { get; set; } = new();
    }
}
