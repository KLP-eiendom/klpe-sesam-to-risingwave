{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Leieobjekt',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for rental object data to Forvalter.
  Mirrors Sesam leieobjekt-forvalter-endpoint.

  Source: mrt_global_rentalobject (stg_d365_leieobjekt).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, Navn, Bygg, Type, ForvalterId, DrifterId, OekonomId, GyldigFra, GyldigTil

*/

SELECT
        {{ test_id("id") }}
id                                          AS "Id",
    navn                                        AS "Navn",
    bygg                                        AS "Bygg",
    utleieobjekt_type                           AS "Type",
    forvalter_epost                             AS "ForvalterId",
    drift_epost                                 AS "DrifterId",
    oekonomi_epost                              AS "OekonomId",
    gyldig_fra                                  AS "GyldigFra",
    gyldig_til                                  AS "GyldigTil",
    '1970-01-01 00:00:00'::TIMESTAMP            AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP            AS "LastUpdated"
FROM {{ ref('stg_d365_leieobjekt') }}
-- Sesam leieobjekt-forvalter keeps only active rows (gyldig_til IS NULL OR gyldig_til > now()).
-- _is_active is computed poll-time by the bigquery-poller from ActiveUntilColumn=gyldig_til
-- (same pattern as stg_d365_contract_line / snk_kunde_leie_superoffice); the gyldig_til IS NULL
-- guard covers rows with no expiry.
WHERE leieobjekt_id IS NOT NULL
  AND (_is_active = true OR gyldig_til IS NULL)
