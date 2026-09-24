{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink', 'powerapp'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:sqlserver://' ~ env_var('POWERAPP_MSSQL_HOST', 'localhost') ~ ':1433;databaseName=' ~ env_var('POWERAPP_MSSQL_DB', 'powerapp-db') ~ ';encrypt=true;trustServerCertificate=true;connectRetryCount=5;connectRetryInterval=10;keepAlive=true;loginTimeout=60;',
        'user': env_var('POWERAPP_MSSQL_USER', ''),
        'password': env_var('POWERAPP_MSSQL_PASSWORD', ''),
        'table.name': 'BrukerRolle',
        'schema.name': 'dbo',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id',
        'sink.parallelism': '1'
    }
) }}
{% else %}
{{ config(
    materialized='view',
    tags=['sink', 'powerapp']
) }}
{% endif %}

SELECT
    {{ test_id("CAST(Id AS VARCHAR)") }}
    Id AS "Id",
    BrukerId AS "BrukerId",
    Rolle AS "Rolle",
    Region as "Region",
    CASE WHEN Created IS NULL OR Created < '1753-01-01'::TIMESTAMP THEN '1753-01-01 00:00:00'::TIMESTAMP ELSE Created END AS "Created",
    CASE WHEN LastUpdated IS NULL OR LastUpdated < '1753-01-01'::TIMESTAMP THEN NULL ELSE LastUpdated END AS "LastUpdated"
FROM {{ ref('stg_forvalter_brukerrolle') }}
WHERE Id IS NOT NULL
