# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# For Web API
EXPOSE 8080

COPY out .

ENTRYPOINT ["dotnet", "RisingWaveDataApi.dll"]
