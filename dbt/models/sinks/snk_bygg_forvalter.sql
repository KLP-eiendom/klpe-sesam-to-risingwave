{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Bygg',
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
  MySQL sink for property data to Forvalter.
  Mirrors Sesam bygg-forvalter-endpoint.

  Source: mrt_global_property.

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, Nummer, Navn, Adresse, Type, FirmaId, ForvalterId, DrifterId,
                OekonomId, PostNummer, Sted, Region, TotaltAreal, LedigAreal,
                LedigArealMarkedspris, HovedVisningsBilde, EnergiKarakter,
                OppvarmingKarakter, AndelFossilEl, EnergiForbruk

  Gap vs Sesam:
    FirmaId — Sesam fallbacks to grunneiendom:firma_id and substring(avdeling_id, 0, 4); using ba_firma_id only.
*/

SELECT
        {{ test_id("COALESCE(bygg_id, bygg_avdeling_id)") }}
bygg_avdeling_id                              AS "Id",
    bygg_avdeling_id                              AS "Nummer",
    COALESCE(ba_navn, b_navn, fb_byggnavn)        AS "Navn",
    COALESCE(fb_adresse, b_adresse)               AS "Adresse",
    COALESCE(b_bygg_type, avdeling_type)          AS "Type",
    ba_firma_id                                   AS "FirmaId",
    b_postnummer                                  AS "PostNummer",
    b_by                                          AS "Sted",
    "bildearkivLink"                              AS "HovedVisningsBilde",
    andelfossilt                                  AS "AndelFossilEl",
    energiforbruk                                 AS "EnergiForbruk",
    COALESCE(totalphysicalarea::DOUBLE PRECISION, 0)      AS "TotaltAreal",
    COALESCE(totalvacantarea::DOUBLE PRECISION, 0)        AS "LedigAreal",
    COALESCE(marketpricevacantarea::DOUBLE PRECISION, 0)  AS "LedigArealMarkedspris",
    LOWER(COALESCE(forvalter_epost, eiendomsansv))        AS "ForvalterId",
    LOWER(COALESCE(drift_epost, driftsansv))              AS "DrifterId",
    LOWER(oekonomi_epost)                                 AS "OekonomId",
    region                                                AS "Region",
    energycategory                                        AS "EnergiKarakter",
    heatingcategory                                       AS "OppvarmingKarakter",
    COALESCE(b_gyldig_fra::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    COALESCE(b_gyldig_fra::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated"
FROM {{ ref('mrt_bygg_forvalter') }}
WHERE bygg_avdeling_id IS NOT NULL
