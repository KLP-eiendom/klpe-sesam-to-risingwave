{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink', 'powerapp'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:sqlserver://' ~ env_var('POWERAPP_MSSQL_HOST', 'localhost') ~ ':1433;databaseName=' ~ env_var('POWERAPP_MSSQL_DB', 'powerapp-db') ~ ';encrypt=true;trustServerCertificate=true;connectRetryCount=5;connectRetryInterval=10;keepAlive=true;loginTimeout=60;',
        'user': env_var('POWERAPP_MSSQL_USER', ''),
        'password': env_var('POWERAPP_MSSQL_PASSWORD', ''),
        'table.name': 'ProsjektProsess',
        'schema.name': 'dbo',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'ProsjektId,ProsessInstansId',
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
        {{ test_id("ProsjektId || '_' || ProsessInstansId") }}
    ProsjektId AS "ProsjektId",
    ProsessInstansId AS "ProsessInstansId",
    Byggnummer AS "Byggnummer",
    D365ProsjektId AS "D365ProsjektId",
    Forvaltningsdirektor AS "Forvaltningsdirektor",
    OpprettetAv AS "OpprettetAv",
    Prosjekteier AS "Prosjekteier",
    Prosjektleder AS "Prosjektleder",
    Prosjektkontroller AS "Prosjektkontroller",
    Teknisksjef AS "Teknisksjef",
    Utviklingsdirektor AS "Utviklingsdirektor",
    RegistreringStatus AS "RegistreringStatus",
    Steg AS "Steg",
    Type AS "Type",
    SuperOfficeDocumentId AS "SuperOfficeDocumentId",
    ProsjektlederHarAvholdtMote AS "ProsjektkontrollerHarDeltattPaaMote",
    ProsjektlederHarAvholdtMote AS "ProsjektlederHarAvholdtMote",
    Created AS "Created",
    LastUpdated AS "LastUpdated"
FROM {{ ref('stg_forvalter_prosjektprosess') }}
WHERE ProsjektId IS NOT NULL AND ProsessInstansId IS NOT NULL
