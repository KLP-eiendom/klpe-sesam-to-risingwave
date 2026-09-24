{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink', 'powerapp'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:sqlserver://' ~ env_var('POWERAPP_MSSQL_HOST', 'localhost') ~ ':1433;databaseName=' ~ env_var('POWERAPP_MSSQL_DB', 'powerapp-db') ~ ';encrypt=true;trustServerCertificate=true;connectRetryCount=5;connectRetryInterval=10;keepAlive=true;loginTimeout=60;',
        'user': env_var('POWERAPP_MSSQL_USER', ''),
        'password': env_var('POWERAPP_MSSQL_PASSWORD', ''),
        'table.name': 'Processinstance',
        'schema.name': 'dbo',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'id_',
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
        {{ test_id("id_") }}
    id_,
    proc_inst_id_,
    proc_def_key_,
    business_key_,
    start_time_,
    end_time_,
    duration_,
    delete_reason_,
    state_
FROM {{ ref('stg_camunda_act_hi_procinst') }}
WHERE id_ IS NOT NULL
  AND (proc_def_key_ LIKE 'prosjekt%' OR proc_def_key_ LIKE 'tiltak%')
  AND (state_ != 'EXTERNALLY_TERMINATED' OR state_ IS NULL)
