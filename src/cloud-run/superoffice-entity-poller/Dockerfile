# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Install Python 3 (minimal, no pip cache) for the Kafka auth proxy sidecar
RUN apt-get update && \
  apt-get install -y --no-install-recommends python3 && \
  rm -rf /var/lib/apt/lists/*

COPY out .

# Entrypoint: start the auth proxy in the background, then run the .NET job.
# 'exec dotnet' replaces the shell so the process receives signals correctly.
ENTRYPOINT ["/bin/sh", "-c", \
  "exec dotnet SuperOfficeEntityPoller.dll"]

