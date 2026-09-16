# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

COPY out .

ENTRYPOINT ["/bin/sh", "-c", \
  "exec dotnet SinkErrorCollector.dll"]
