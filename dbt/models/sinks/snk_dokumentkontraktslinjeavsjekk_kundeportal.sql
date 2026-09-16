{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'DokumentKontraktlinje',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'DokumentId,KontraktlinjeId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

SELECT
        {{ test_id("(DokumentId)::VARCHAR || '_' || (KontraktLinjeId)::VARCHAR") }}
    DokumentId      AS "DokumentId",
    KontraktLinjeId AS "KontraktlinjeId",
    COALESCE(Created, TIMESTAMP '1970-01-01 00:00:00') AS "Created",
    LastUpdated     AS "LastUpdated"
FROM {{ ref('stg_forvalter_dokumentkontraktslinjeavsjekk') }}
WHERE DokumentId IS NOT NULL
  AND KontraktLinjeId IS NOT NULL
