{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('MILJOPROFIL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('MILJOPROFIL_MYSQL_PORT', '3306') ~ '/' ~ env_var('MILJOPROFIL_MYSQL_DB', 'miljoprofil-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('MILJOPROFIL_MYSQL_USER', ''),
        'password': env_var('MILJOPROFIL_MYSQL_PASSWORD', ''),
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
  MySQL sink for property data to Miljoprofil.
  Mirrors Sesam bygg-miljoprofil-endpoint.

  Source: mrt_bygg_forvalter (shared enriched-bygg mart over mrt_global_property).

  MySQL target (MiljoprofilCommonDAL.ByggEntity):
    ByggId            varchar(255) PK
    Beskrivelse, Navn, Adresse, By, Poststed, Postnummer, Fylke, Region,
    GABNummer, EiendomsNummer, ByggNummer, KompleksNummer (int),
    Etasjer, FdvWebByggId, ByggNavnId, Bygningsnavn, GnrBnr, Markedsomrade,
    TotAreal, TotEietAreal, TotLeietAreal, TomtAreal,
    Eier, Eiendomsansv, Forvalter_epost, Driftsansv, Driftsjef_epost, Driftsteknikker,
    Byggherre, Arkitekt, Byggeaar, Beliggenhet, Historikk,
    HovedVisningsBilde, BimSyncProjectId,
    EnergiKarakter, EnergiForbruk (decimal), OppvarmingKarakter, Type,
    AndelFossilEl (decimal), Longitude (double), Latitude (double), OppvarmetAreal,
    Created, LastUpdated

  Required environment variables:
    MILJOPROFIL_MYSQL_HOST     e.g. localhost (shared with Forvalter/Kundeportal)
    MILJOPROFIL_MYSQL_PORT     e.g. 3306
    MILJOPROFIL_MYSQL_USER     MySQL username
    MILJOPROFIL_MYSQL_PASSWORD MySQL password
    MILJOPROFIL_MYSQL_DB       Miljoprofil database name

  Gap vs Sesam:
    BimSyncProjectId, Latitude, Longitude — historically populated by other
    Miljoprofil sources (axapta-building, kundeportal-building); not present in
    mrt_global_property today. Written as NULL — Miljoprofil retains the prior
    values because RisingWave upsert only updates the columns it sends.
    TomtAreal — Sesam reads from fdvweb-building:tomtAreal; not yet exposed in
    mrt_global_property. Written as NULL.
*/

SELECT
    {{ test_id("COALESCE(bygg_id, bygg_avdeling_id)") }}
    bygg_avdeling_id                                                          AS "ByggId",
    beskrivelse                                                               AS "Beskrivelse",
    COALESCE(bygningsnavn, b_navn, ba_navn)                                   AS "Navn",
    COALESCE(fb_adresse, b_adresse)                                           AS "Adresse",
    b_by                                                                      AS "By",
    b_by                                                                      AS "Poststed",
    b_postnummer                                                              AS "Postnummer",
    fylke                                                                     AS "Fylke",
    region                                                                    AS "Region",
    "GABnr"                                                                   AS "GABNummer",
    COALESCE(eiendom_id, bygg_avdeling_id)                                    AS "EiendomsNummer",
    COALESCE(bygg_id, bygg_avdeling_id)                                       AS "ByggNummer",
    NULLIF(REGEXP_REPLACE(TRIM(kompleksnr), '[^0-9]', '', 'g'), '')::INT      AS "KompleksNummer",
    etasjer                                                                   AS "Etasjer",
    fb_id                                                                     AS "FdvWebByggId",
    LOWER(fb_byggnavnid)                                                      AS "ByggNavnId",
    bygningsnavn                                                              AS "Bygningsnavn",
    "GnrBnr"                                                                  AS "GnrBnr",
    markedsomrade                                                             AS "Markedsomrade",
    COALESCE(totalphysicalarea::DOUBLE PRECISION, 0)::VARCHAR                 AS "TotAreal",
    COALESCE(totalphysicalarea::DOUBLE PRECISION, 0)::VARCHAR                 AS "TotEietAreal",
    COALESCE(totalrentedarea::DOUBLE PRECISION, 0)::VARCHAR                   AS "TotLeietAreal",
    NULL::VARCHAR                                                             AS "TomtAreal",
    COALESCE(eier, NULLIF(b_firma_id, ''))                                    AS "Eier",
    eiendomsansv                                                              AS "Eiendomsansv",
    LOWER(forvalter_epost)                                                    AS "Forvalter_epost",
    driftsansv                                                                AS "Driftsansv",
    LOWER(drift_epost)                                                        AS "Driftsjef_epost",
    driftsteknikker                                                           AS "Driftsteknikker",
    byggherre                                                                 AS "Byggherre",
    arkitekt                                                                  AS "Arkitekt",
    COALESCE(fb_byggeaar, byggeaar::VARCHAR)                                  AS "Byggeaar",
    beliggenhet                                                               AS "Beliggenhet",
    historikk                                                                 AS "Historikk",
    "bildearkivLink"                                                          AS "HovedVisningsBilde",
    NULL::VARCHAR                                                             AS "BimSyncProjectId",
    energycategory                                                            AS "EnergiKarakter",
    COALESCE(energiforbruk, 0)::DECIMAL                                       AS "EnergiForbruk",
    heatingcategory                                                           AS "OppvarmingKarakter",
    COALESCE(b_bygg_type, avdeling_type)                                      AS "Type",
    COALESCE(andelfossilt, 0)::DECIMAL                                        AS "AndelFossilEl",
    NULL::DOUBLE PRECISION                                                    AS "Longitude",
    NULL::DOUBLE PRECISION                                                    AS "Latitude",
    fb_oppvarmet_areal                                                        AS "OppvarmetAreal",
    '1970-01-01 00:00:00'::TIMESTAMP                                          AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                                          AS "LastUpdated"
FROM {{ ref('mrt_bygg_forvalter') }}
WHERE bygg_avdeling_id IS NOT NULL
  -- Exclude d365-building-only records (no bygg-avdeling). Sesam keys those by
  -- BuildingId/BUILDINGID here (a field RW doesn't have), so they can't reach ID-parity;
  -- they remain in snk_bygg_forvalter/snk_bygg_bqeos (where Sesam keys by bygg_id, which we match).
  AND has_avdeling
