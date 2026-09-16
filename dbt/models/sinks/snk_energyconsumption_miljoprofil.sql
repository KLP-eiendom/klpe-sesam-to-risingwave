{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('MILJOPROFIL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('MILJOPROFIL_MYSQL_PORT', '3306') ~ '/' ~ env_var('MILJOPROFIL_MYSQL_DB', 'miljoprofil-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('MILJOPROFIL_MYSQL_USER', ''),
        'password': env_var('MILJOPROFIL_MYSQL_PASSWORD', ''),
        'table.name': 'MaalerDataPerMndPerBygg',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'UniqueId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  MySQL sink for monthly energy consumption to Miljoprofil.
  Mirrors Sesam energyconsumption-miljoprofil-endpoint.

  Source: stg_energinet_energyconsumption (BigQuery/Energinet poller).

  Sesam DTL (energyconsumption-miljoprofil global pipe):
    ByggNummer ← BuildingId, Type ← Type, Unit ← unit, Sum ← Sum, Mnd ← Mnd,
    EksternId ← MeteringpointId, System ← 'Energinet',
    filter unit != 'C' AND ByggNummer NOT NULL.

  MySQL target (MiljoprofilCommonDAL.MaalerDataPerMndPerByggEntity, post
  20260426171026_RefactorToUniqueId): UniqueId varchar(255) PK.
*/

SELECT
    {{ test_id("CONCAT(BuildingId, '-', COALESCE(MeteringpointId, ''), '-', MndString, '-', Type, '-', unit)::VARCHAR") }}
    CONCAT(BuildingId, '-', COALESCE(MeteringpointId, ''), '-', MndString, '-', Type, '-', unit) AS "UniqueId",
    BuildingId                       AS "ByggNummer",
    MeteringpointId                  AS "EksternId",
    Mnd::INT                         AS "Mnd",
    Type                             AS "Type",
    unit                             AS "Unit",
    Sum::DECIMAL                     AS "Sum",
    'Energinet'::VARCHAR             AS "System",
    '1970-01-01 00:00:00'::TIMESTAMP AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP AS "LastUpdated"
FROM {{ ref('stg_energinet_energyconsumption') }}
WHERE BuildingId IS NOT NULL
  AND unit != 'C'
