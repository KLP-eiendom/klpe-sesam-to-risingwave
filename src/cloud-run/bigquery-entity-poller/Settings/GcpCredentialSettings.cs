namespace BigQueryEntityPoller.Settings
{
    /// <summary>
    /// Holds the GCP service account JSON credentials fetched from Vault.
    /// When empty the poller falls back to Application Default Credentials (ADC),
    /// which works automatically on Cloud Run via Workload Identity.
    /// </summary>
    public class GcpCredentialSettings
    {
        public string Value { get; set; } = string.Empty;
    }
}
