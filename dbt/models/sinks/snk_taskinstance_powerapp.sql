{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink', 'powerapp'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:sqlserver://' ~ env_var('POWERAPP_MSSQL_HOST', 'localhost') ~ ':1433;databaseName=' ~ env_var('POWERAPP_MSSQL_DB', 'powerapp-db') ~ ';encrypt=true;trustServerCertificate=true;connectRetryCount=5;connectRetryInterval=10;keepAlive=true;loginTimeout=60;',
        'user': env_var('POWERAPP_MSSQL_USER', ''),
        'password': env_var('POWERAPP_MSSQL_PASSWORD', ''),
        'table.name': 'Taskinstance',
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
    ti.id_,
    ti.task_def_key_,
    ti.proc_inst_id_,
    ti.proc_def_key_,
    ti.act_inst_id_,
    ti.name_,
    ti.owner_,
    ti.assignee_,
    ti.start_time_,
    ti.end_time_,
    ti.duration_,
    ti.delete_reason_,
    ti.task_state_,
    pst.ownerRole AS "owner_role"
FROM {{ ref('stg_camunda_act_hi_taskinst') }} ti
LEFT JOIN {{ ref('stg_eiendom_prosjektsortedusertask') }} pst
    ON (ti.proc_def_key_ || '_' || ti.task_def_key_) = pst._id
WHERE ti.id_ IS NOT NULL
  AND (ti.proc_def_key_ LIKE 'prosjekt%' OR ti.proc_def_key_ LIKE 'tiltak%')
  AND (ti.delete_reason_ IS NULL OR ti.delete_reason_ != 'Deleted')
