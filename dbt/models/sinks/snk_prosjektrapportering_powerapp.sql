{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink', 'powerapp'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:sqlserver://' ~ env_var('POWERAPP_MSSQL_HOST', 'localhost') ~ ':1433;databaseName=' ~ env_var('POWERAPP_MSSQL_DB', 'powerapp-db') ~ ';encrypt=true;trustServerCertificate=true;connectRetryCount=5;connectRetryInterval=10;keepAlive=true;loginTimeout=60;',
        'user': env_var('POWERAPP_MSSQL_USER', ''),
        'password': env_var('POWERAPP_MSSQL_PASSWORD', ''),
        'table.name': 'Prosjektrapport',
        'schema.name': 'dbo',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'ProsjektId',
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
    {{ test_id("prosjekt_id") }}
    prosjekt_id AS "ProsjektId"
FROM {{ ref('stg_d365_prosjekt') }}
WHERE prosjekt_id IS NOT NULL
  AND (sortering_3 != '09TID' OR sortering_3 IS NULL)
  AND (Origin != 'D365 Budsjettprosjekt' OR Origin IS NULL)
  AND (prosjekt_gruppe_id NOT LIKE 'MIG%' OR prosjekt_gruppe_id IS NULL)
