{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink', 'powerapp'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:sqlserver://' ~ env_var('POWERAPP_MSSQL_HOST', 'localhost') ~ ':1433;databaseName=' ~ env_var('POWERAPP_MSSQL_DB', 'powerapp-db') ~ ';encrypt=true;trustServerCertificate=true;connectRetryCount=5;connectRetryInterval=10;keepAlive=true;loginTimeout=60;',
        'user': env_var('POWERAPP_MSSQL_USER', ''),
        'password': env_var('POWERAPP_MSSQL_PASSWORD', ''),
        'table.name': 'Bruker',
        'schema.name': 'dbo',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'epost',
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
    -- Sesam: coalesce(d365-ansatt:fult_navn, concat(SO firstName, " ", SO lastName)) — for
    -- non-employees the mart's fult_navn holds SO's own fullName, which can include a middle
    -- name SO computes internally and Sesam's firstName+lastName concat does not.
    CASE WHEN is_employee THEN fult_navn ELSE TRIM(CONCAT(so_firstName, ' ', so_lastName)) END AS navn,
    bruker_id AS "brukerId",
    email AS "epost"
FROM {{ ref('mrt_global_internaluser') }}
