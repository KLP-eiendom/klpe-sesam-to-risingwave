{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink', 'powerapp'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:sqlserver://' ~ env_var('POWERAPP_MSSQL_HOST', 'localhost') ~ ':1433;databaseName=' ~ env_var('POWERAPP_MSSQL_DB', 'powerapp-db') ~ ';encrypt=true;trustServerCertificate=true;connectRetryCount=5;connectRetryInterval=10;keepAlive=true;loginTimeout=60;',
        'user': env_var('POWERAPP_MSSQL_USER', ''),
        'password': env_var('POWERAPP_MSSQL_PASSWORD', ''),
        'table.name': 'Prosjekt',
        'schema.name': 'dbo',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'prosjekt_id',
        'sink.parallelism': '1'
    }
) }}
{% else %}
{{ config(
    materialized='view',
    tags=['sink', 'powerapp']
) }}
{% endif %}

WITH source AS (
    SELECT
        *
    FROM {{ ref('stg_d365_prosjekt') }}
    WHERE prosjekt_id IS NOT NULL
)
SELECT
    prosjekt_id,
    kostnadsfordelingsprosent,
    Origin AS "Origin",
    prosjekt_opprettet,
    prosjekt_navn,
    prosjekt_gruppe_id,
    sortering_1,
    sortering_2,
    sortering_3,
    dato_opprettet,
    dato_utvidet,
    startdato_planlagt,
    startdato_faktisk,
    sluttdato_planlagt,
    sluttdato_faktisk,
    overlevering_faktisk,
    sluttdato_revidert,
    overlevering_planlagt,
    overlevering_revidert,
    tiltakstype,
    ansvarlig_forvalter_id,
    ansvarlig_kontroller_id,
    ansvarlig_prosjektleder_id,
    byggavdeling_id,
    leieobjekt_id,
    kunde_id,
    kontrakt_id,
    status,
    prosjekt_id_parent,
    juridiskenhet,
    ansvarlig_forvalter_navn,
    ansvarlig_prosjektleder_navn,
    ansvarlig_kontroller_navn,
    ProsjektKey AS "ProsjektKey",
    ProsjektKey_Upper AS "ProsjektKey_Upper"
FROM source
