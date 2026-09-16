{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('MILJOPROFIL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('MILJOPROFIL_MYSQL_PORT', '3306') ~ '/' ~ env_var('MILJOPROFIL_MYSQL_DB', 'miljoprofil-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('MILJOPROFIL_MYSQL_USER', ''),
        'password': env_var('MILJOPROFIL_MYSQL_PASSWORD', ''),
        'table.name': 'AvfallDataPerMnd',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'UniqueId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  MySQL sink for monthly waste data to Miljoprofil.
  Mirrors Sesam wasteconsumption-miljoprofil-endpoint.

  Source: stg_energinet_wasteconsumption.

  Sesam DTL (wasteconsumption-miljoprofil global pipe):
    ByggNummer ← BuildingId,
    Beskrivelse ← if Type matches "(Ingen*" then Type else substring(5..) of Type,
    TypeKode    ← if Type matches "(Ingen*" then Type else substring(0,4) of Type,
    Unit, Sum, Mnd, EksternId ← MeteringpointId, System ← 'Energinet',
    filter ByggNummer NOT NULL.

  MySQL target (AvfallDataPerMndEntity, post 20260426171026_RefactorToUniqueId):
    UniqueId varchar(255) PK = _id (composite from upstream Sesam).
*/

SELECT
    {{ test_id("_id") }}
    _id                                                                    AS "UniqueId",
    _id                                                                    AS "EksternId",
    BuildingId                                                             AS "ByggNummer",
    CASE WHEN Type LIKE '(Ingen%' THEN Type ELSE LEFT(Type, 4)          END AS "TypeKode",
    CASE WHEN Type LIKE '(Ingen%' THEN Type ELSE SUBSTRING(Type FROM 6) END AS "Beskrivelse",
    Mnd::INT                                                               AS "Mnd",
    Sum::DECIMAL                                                           AS "Sum",
    'Energinet'::VARCHAR                                                   AS "System",
    '1970-01-01 00:00:00'::TIMESTAMP                                       AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                                       AS "LastUpdated"
FROM {{ ref('stg_energinet_wasteconsumption') }}
WHERE BuildingId IS NOT NULL
