{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('MILJOPROFIL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('MILJOPROFIL_MYSQL_PORT', '3306') ~ '/' ~ env_var('MILJOPROFIL_MYSQL_DB', 'miljoprofil-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('MILJOPROFIL_MYSQL_USER', ''),
        'password': env_var('MILJOPROFIL_MYSQL_PASSWORD', ''),
        'table.name': 'MaalerDataPerMndPerKunde',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'UniqueId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  MySQL sink for monthly customer-level energy consumption to Miljoprofil.
  Mirrors Sesam energycustomerconsumption-miljoprofil-endpoint.

  Source: stg_energinet_energycustomerconsumption.

  Sesam DTL (energycustomerconsumption-miljoprofil global pipe):
    ByggNummer ← BuildingId, Type, Unit ← unit, Sum, Mnd,
    Kundenummer ← CustomerNumber, System ← 'Energinet',
    filter unit != 'C' AND ByggNummer NOT NULL.

  PRE-REQUISITE: requires MiljoprofilCommonDAL migration that adds
  `UniqueId varchar(255) PRIMARY KEY` to MaalerDataPerMndPerKunde
  (parallel to 20260426171026_RefactorToUniqueId for the *PerBygg table).
  Until that migration ships, this sink will fail to deploy — keep
  MILJOPROFIL_SINK_MODE=paused.
*/

SELECT
    {{ test_id("CONCAT(BuildingId, '-', Type, '-', unit, '-', Mnd::VARCHAR, '-', CustomerNumber)::VARCHAR") }}
    CONCAT(BuildingId, '-', Type, '-', unit, '-', Mnd::VARCHAR, '-', CustomerNumber) AS "UniqueId",
    BuildingId                       AS "ByggNummer",
    CustomerNumber                   AS "KundeNummer",
    Mnd::INT                         AS "Mnd",
    Type                             AS "Type",
    unit                             AS "Unit",
    Sum::DECIMAL                     AS "Sum",
    'Energinet'::VARCHAR             AS "System",
    '1970-01-01 00:00:00'::TIMESTAMP AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP AS "LastUpdated"
FROM {{ ref('stg_energinet_energycustomerconsumption') }}
WHERE BuildingId IS NOT NULL
  AND unit != 'C'
