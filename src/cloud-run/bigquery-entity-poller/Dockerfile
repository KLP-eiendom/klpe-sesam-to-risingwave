# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

COPY out .

# Entrypoint: run the .NET job directly.
# BigQuery uses GCP credentials (ADC / service account) — no Kafka proxy needed.
ENTRYPOINT ["dotnet", "BigQueryEntityPoller.dll"]
