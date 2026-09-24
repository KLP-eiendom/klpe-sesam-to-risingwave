{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Bygg',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'ByggId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for property data to Kundeportal.
  Mirrors Sesam bygg-kundeportal-endpoint.

  Source: mrt_bygg_kundeportal.

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_DB             Kundeportal database name

  Sesam fields: ByggId, ByggNummer, ByggNavnId, FdvWebByggId, Navn, Adresse,
                GABNummer, EiendomsNummer, KompleksNummer, GnrBnr, Markedsomrade,
                Etasjer, TotEietAreal, TotLeietAreal, Eier, Eiendomsansv, Driftsansv,
                Driftsteknikker, Byggherre, Arkitekt, Byggeaar, Beliggenhet, AndelFossilEl,
                EnergiForbruk, Beskrivelse, Historikk, HovedVisningsBilde, By, Fylke,
                Postnummer, Type, Region, OppvarmetAreal

  Gap vs Sesam:
    BimSyncProjectId, Latitude, Longitude — Kundeportal-managed fields (BIM project ID and
    geo coordinates). In Sesam these were read back from kundeportal-building CDC.
    These fields should be moved to a separate table in Kundeportal (e.g. ByggTillegg)
    so RisingWave does not overwrite them on each upsert. Requires:
      1. EF Core migration in KundeportalCommonDAL — new ByggTillegg table (ByggId FK,
         BimSyncProjectId, Latitude, Longitude); remove columns from Bygg.
      2. stg_kundeportal_byggtillegg CDC staging model in RisingWave.
      3. Remove the NULL columns from this sink (add to separate snk_byggtillegg_kundeportal
         if RisingWave needs to write these fields at all).
*/

SELECT
        {{ test_id("COALESCE(bygg_id, bygg_avdeling_id)") }}
bygg_avdeling_id                                    AS "ByggId",
    COALESCE(bygg_id, bygg_avdeling_id)                 AS "ByggNummer",
    LOWER(fb_byggnavnid)                                AS "ByggNavnId",
    fb_id                                               AS "FdvWebByggId",
    COALESCE(bygningsnavn, b_navn, ba_navn)             AS "Navn",
    COALESCE(fb_adresse, b_adresse)                     AS "Adresse",
    "GABnr"                                             AS "GABNummer",
    COALESCE(eiendom_id, bygg_avdeling_id)              AS "EiendomsNummer",
    NULLIF(REGEXP_REPLACE(TRIM(kompleksnr), '[^0-9]', '', 'g'), '')::INT AS "KompleksNummer",
    "GnrBnr"                                            AS "GnrBnr",
    markedsomrade                                       AS "Markedsomrade",
    etasjer                                             AS "Etasjer",
    COALESCE(totalphysicalarea::DOUBLE PRECISION, 0)    AS "TotEietAreal",
    COALESCE(totalrentedarea::DOUBLE PRECISION, 0)      AS "TotLeietAreal",
    COALESCE(eier, NULLIF(b_firma_id, ''))              AS "Eier",
    eiendomsansv                                        AS "Eiendomsansv",
    driftsansv                                          AS "Driftsansv",
    driftsteknikker                                     AS "Driftsteknikker",
    byggherre                                           AS "Byggherre",
    arkitekt                                            AS "Arkitekt",
    COALESCE(fb_byggeaar, byggeaar::VARCHAR)            AS "Byggeaar",
    beliggenhet                                         AS "Beliggenhet",
    COALESCE(andelfossilt, 0)                           AS "AndelFossilEl",
    COALESCE(energiforbruk, 0)                          AS "EnergiForbruk",
    beskrivelse                                         AS "Beskrivelse",
    historikk                                           AS "Historikk",
    "bildearkivLink"                                    AS "HovedVisningsBilde",
    b_by                                                AS "By",
    fylke                                               AS "Fylke",
    b_postnummer                                        AS "Postnummer",
    COALESCE(b_bygg_type, avdeling_type)                AS "Type",
    region                                              AS "Region",
    energycategory                                      AS "EnergiKarakter",
    heatingcategory                                     AS "OppvarmingKarakter",
    fb_oppvarmet_areal                                  AS "OppvarmetAreal",
    NULL::VARCHAR                                       AS "BimSyncProjectId",
    NULL::DOUBLE PRECISION                              AS "Latitude",
    NULL::DOUBLE PRECISION                              AS "Longitude",
    '1970-01-01 00:00:00'::TIMESTAMP                   AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                   AS "LastUpdated"
FROM {{ ref('mrt_bygg_forvalter') }}
WHERE bygg_avdeling_id IS NOT NULL
  -- Exclude d365-building-only records (no bygg-avdeling). Sesam keys those by
  -- BuildingId/BUILDINGID here (a field RW doesn't have), so they can't reach ID-parity;
  -- they remain in snk_bygg_forvalter/snk_bygg_bqeos (where Sesam keys by bygg_id, which we match).
  AND has_avdeling
