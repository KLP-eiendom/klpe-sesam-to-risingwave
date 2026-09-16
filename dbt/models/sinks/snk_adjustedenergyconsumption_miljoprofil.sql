{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('MILJOPROFIL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('MILJOPROFIL_MYSQL_PORT', '3306') ~ '/' ~ env_var('MILJOPROFIL_MYSQL_DB', 'miljoprofil-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('MILJOPROFIL_MYSQL_USER', ''),
        'password': env_var('MILJOPROFIL_MYSQL_PASSWORD', ''),
        'table.name': 'MaalerDataAdjustedPerMndPerBygg',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'UniqueId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  MySQL sink for monthly adjusted energy consumption to Miljoprofil.
  Mirrors Sesam adjustedenergyconsumption-miljoprofil-endpoint.

  Source: stg_energinet_adjustedenergyconsumption.

  Sesam DTL (adjustedenergyconsumption-miljoprofil global pipe):
    ByggNummer ← BuildingId, Type, Unit ← unit, Sum ← Value, Mnd ← month,
    System ← 'Energinet', filter unit != 'C' AND ByggNummer NOT NULL.
  No EksternId / MeteringpointId in adjusted source.

  PRE-REQUISITE: requires MiljoprofilCommonDAL migration that adds
  `UniqueId varchar(255) PRIMARY KEY` to MaalerDataAdjustedPerMndPerBygg
  (parallel to 20260426171026_RefactorToUniqueId for the *PerBygg table).
  Until that migration ships, this sink will fail to deploy — keep
  MILJOPROFIL_SINK_MODE=paused.
*/

SELECT
    {{ test_id("CONCAT(BuildingId, '-', Type, '-', unit, '-', month)::VARCHAR") }}
    CONCAT(BuildingId, '-', Type, '-', unit, '-', month) AS "UniqueId",
    BuildingId                       AS "ByggNummer",
    month::INT                       AS "Mnd",
    Type                             AS "Type",
    unit                             AS "Unit",
    Value::DECIMAL                   AS "Sum",
    'Energinet'::VARCHAR             AS "System",
    '1970-01-01 00:00:00'::TIMESTAMP AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP AS "LastUpdated"
FROM {{ ref('stg_energinet_adjustedenergyconsumption') }}
WHERE BuildingId IS NOT NULL
  AND unit != 'C'
