{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('MILJOPROFIL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('MILJOPROFIL_MYSQL_PORT', '3306') ~ '/' ~ env_var('MILJOPROFIL_MYSQL_DB', 'miljoprofil-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('MILJOPROFIL_MYSQL_USER', ''),
        'password': env_var('MILJOPROFIL_MYSQL_PASSWORD', ''),
        'table.name': 'Maaltall',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  MySQL sink for emission factors / reference values to Miljoprofil.
  Mirrors Sesam maaltall-miljoprofil-endpoint.

  Source: stg_energinet_maaltall.

  Sesam DTL (maaltall-miljoprofil global pipe):
    filter Type NOT NULL AND Maaltall NOT NULL,
    Type ← Type, Region ← region, Value ← Maaltall,
    Id ← if Region is null then Type else concat(Region, '-', Type).

  MySQL target (MaaltallEntity): Id varchar PK, Value decimal.
*/

SELECT
    {{ test_id("CASE WHEN region IS NULL OR region = '' THEN Type ELSE region || '-' || Type END") }}
    CASE WHEN region IS NULL OR region = '' THEN Type ELSE region || '-' || Type END AS "Id",
    region                             AS "Region",
    Type                               AS "Type",
    Maaltall::DECIMAL                  AS "Value",
    '1970-01-01 00:00:00'::TIMESTAMP   AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP   AS "LastUpdated"
FROM {{ ref('stg_energinet_maaltall') }}
WHERE _id IS NOT NULL
  AND Type IS NOT NULL
  AND Maaltall IS NOT NULL
