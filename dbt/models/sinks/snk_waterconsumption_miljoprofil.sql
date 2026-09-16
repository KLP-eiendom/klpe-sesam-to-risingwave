{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('MILJOPROFIL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('MILJOPROFIL_MYSQL_PORT', '3306') ~ '/' ~ env_var('MILJOPROFIL_MYSQL_DB', 'miljoprofil-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('MILJOPROFIL_MYSQL_USER', ''),
        'password': env_var('MILJOPROFIL_MYSQL_PASSWORD', ''),
        'table.name': 'VannDataPerMnd',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  MySQL sink for monthly water consumption to Miljoprofil.
  Mirrors Sesam waterconsumption-miljoprofil-endpoint.

  Source: stg_energinet_waterconsumption.

  Sesam DTL (waterconsumption-miljoprofil global pipe):
    Id ← concat(BuildingId, '-', Mnd)
    ByggNummer ← BuildingId, Type, Unit ← unit, Sum, Mnd,
    EksternId ← MeteringpointId, System ← 'Energinet',
    filter ByggNummer NOT NULL (no unit != 'C' filter for water).

  MySQL target (VannDataPerMndEntity): Id varchar PK = BuildingId-Mnd.
*/

SELECT
    {{ test_id("CONCAT(BuildingId, '-', COALESCE(Mnd::VARCHAR, ''))::VARCHAR") }}
    CONCAT(BuildingId, '-', COALESCE(Mnd::VARCHAR, ''))  AS "Id",
    BuildingId                       AS "ByggNummer",
    MeteringpointId                  AS "EksternId",
    Mnd::INT                         AS "Mnd",
    Type                             AS "Type",
    unit                             AS "Unit",
    Sum::DECIMAL                     AS "Sum",
    'Energinet'::VARCHAR             AS "System",
    '1970-01-01 00:00:00'::TIMESTAMP AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP AS "LastUpdated"
FROM {{ ref('stg_energinet_waterconsumption') }}
WHERE BuildingId IS NOT NULL
