{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Kontraktlinje',
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
  MySQL sink for contract line data to Forvalter.
  Mirrors Sesam contract-details-forvalter-endpoint.

  Source: mrt_contract_details_forvalter.

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, KundeNummer, KontraktsNummer, ByggNummer, KontraktsNavn,
                LinjeNavn, LinjeType, KontraktGyldigFra, KontraktGyldigTil,
                LinjeGyldigFra, LinjeGyldigTil, Areal, ArealType, ArealTypeNavn,
                Antall, FysiskAreal, LeieEnhet, LeieKostTypeId, LeieKostTypeNavn,
                LeieKostGruppeId, LeieartGruppeId, LeieartGruppeKode, LeieartGruppeN1,
                LeieobjektId, MaanedligBeloep, AarligBeloep, ArealUnntattBeregning,
                KontraktDato, Region, OrgNivaa2, OrgNivaa3, ByggId, KundeId

  Gap vs Sesam:
    LastUpdated — no update timestamp in stg_d365_contract_line or stg_d365_kontrakt; falls back to 1900-01-01.
*/

SELECT
        {{ test_id("cl.unik_id::VARCHAR") }}
cl.unik_id::VARCHAR                                              AS "Id",
    k.kundenummer                                                    AS "KundeNummer",
    CONCAT(cl.kontrakt_nummer, '.', UPPER(cl.firma))                 AS "KontraktsNummer",
    NULLIF(k.byggnummer, '')                                         AS "ByggNummer",
    k.kontrakt_navn                                                  AS "KontraktsNavn",
    cl.linje_type                                                    AS "LinjeType",
    LEFT(cl.navn, 50)                                                AS "LinjeNavn",
    k.gyldig_fra                                                     AS "KontraktGyldigFra",
    k.gyldig_til                                                     AS "KontraktGyldigTil",
    cl.gyldig_fra                                                    AS "LinjeGyldigFra",
    cl.gyldig_til                                                    AS "LinjeGyldigTil",
    cl.areal                                                         AS "Areal",
    cl.areal_type                                                    AS "ArealType",
    cl.areal_type_navn                                               AS "ArealTypeNavn",
    CASE WHEN cl.leie_enhet = 'm2' THEN 0
         ELSE COALESCE(cl.leie_antall, 0)
    END                                                              AS "Antall",
    COALESCE(cl.fysisk_areal, 0)                                    AS "FysiskAreal",
    cl.leie_enhet                                                    AS "LeieEnhet",
    LEFT(cl.leie_kost_type_id, 19)                                   AS "LeieKostTypeId",
    LEFT(cl.leie_kost_type_navn, 19)                                 AS "LeieKostTypeNavn",
    cl.leie_kost_gruppe_id                                           AS "LeieKostGruppeId",
    cl.leie_art_gruppe_id                                            AS "LeieartGruppeId",
    cl.leie_art_gruppe_kode                                          AS "LeieartGruppeKode",
    cl.leie_art_gruppe_n1                                            AS "LeieartGruppeN1",
    cl.leie_objekt_id                                                AS "LeieObjektId",
    COALESCE(cl.maanedlig_beloep, 0)                                AS "MaanedligBeloep",
    COALESCE(cl.aarlig_beloep, 0)                                   AS "AarligBeloep",
    cl.areal_ikke_medregnet > 0                                      AS "ArealUnntattBeregning",
    cl.kontrakt_dato                                                 AS "KontraktDato",
    COALESCE(f.region, '')                                           AS "Region",
    COALESCE(f.orglevel2, '')                                        AS "OrgNivaa2",
    COALESCE(f.orglevel3, '')                                        AS "OrgNivaa3",
    -- NB: Sesam's contract-details-forvalter DTL computes ByggId/KundeId into its DATASET,
    -- but the real Kontraktlinje table has NO such columns — Sesam's SQL endpoint silently
    -- drops them on write. RW validates strictly, so DO NOT emit them (deploy fails otherwise).
    -- The Tier-2 byggid/kundeid "diff" is a validator artifact (reads Sesam source) → blacklisted.
    COALESCE(cl.kontrakt_dato::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                                 AS "LastUpdated"
FROM {{ ref('stg_d365_contract_line') }} cl
-- Resolve the ONE owning kontrakt (utleier) per line, mirroring Sesam's hop
-- (concat(kontrakt_nummer,'.',firma) == lower(kontrakt.unique_id)) and the kundeportal twin.
-- Joining on kontrakt_id alone fans out across every firma/utleier variant of the kontrakt,
-- landing a non-deterministic byggnummer/kundenummer/kontrakt_navn/gyldig date after PK-upsert.
LEFT JOIN {{ ref('stg_d365_kontrakt') }} k
    ON LOWER(CONCAT(cl.kontrakt_nummer, '.', cl.firma)) = LOWER(k._id)
LEFT JOIN {{ ref('stg_d365_firma') }} f
    ON UPPER(cl.firma) = f.firma_id
WHERE cl.unik_id IS NOT NULL
  AND k.kundenummer IS NOT NULL
