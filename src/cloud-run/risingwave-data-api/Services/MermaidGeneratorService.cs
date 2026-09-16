using System.Collections.Generic;
using System.Text;
using RisingWaveDataApi.Models;

namespace RisingWaveDataApi.Services
{
    public class MermaidGeneratorService : IMermaidGeneratorService
    {
        public string GenerateFlowchart(List<SystemIntegration> systems)
        {
            var sb = new StringBuilder();
            sb.AppendLine("flowchart LR");
            sb.AppendLine("    %% Center Node");
            sb.AppendLine("    RW((\"RisingWave\\nDatahub\"))");
            sb.AppendLine();

            var incoming = new List<string>();
            var bidirectional = new List<string>();
            var outgoing = new List<string>();

            int i = 0;
            foreach (var sys in systems)
            {
                var nodeId = $"N{i++}";
                var nodeLabel = $"{nodeId}[\"{sys.SystemName}\"]";

                if (sys.FlowDirection == "Bidirectional")
                {
                    bidirectional.Add($"{nodeLabel} <--> RW");
                }
                else if (sys.FlowDirection == "In Only")
                {
                    incoming.Add($"{nodeLabel} --> RW");
                }
                else if (sys.FlowDirection == "Out Only")
                {
                    outgoing.Add($"RW --> {nodeLabel}");
                }
            }

            if (incoming.Count > 0)
            {
                sb.AppendLine("    %% Incoming Systems (Left)");
                foreach (var line in incoming)
                {
                    sb.AppendLine($"    {line}");
                }

                sb.AppendLine();
            }

            if (bidirectional.Count > 0)
            {
                sb.AppendLine("    %% Bidirectional Systems (Top/Bottom)");
                foreach (var line in bidirectional)
                {
                    sb.AppendLine($"    {line}");
                }

                sb.AppendLine();
            }

            if (outgoing.Count > 0)
            {
                sb.AppendLine("    %% Outgoing Systems (Right)");
                foreach (var line in outgoing)
                {
                    sb.AppendLine($"    {line}");
                }

                sb.AppendLine();
            }

            sb.AppendLine("    classDef centerNode fill:#1f77b4,color:white,font-weight:bold,stroke-width:0px;");
            sb.AppendLine("    class RW centerNode;");

            return sb.ToString();
        }
    }
}
