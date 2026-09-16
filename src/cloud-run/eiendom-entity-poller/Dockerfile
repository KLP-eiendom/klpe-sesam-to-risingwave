# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

COPY out .

ENTRYPOINT ["dotnet", "EiendomEntityPoller.dll"]
