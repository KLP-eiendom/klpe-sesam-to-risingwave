{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'KontraktDetaljer',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'UniqueId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

SELECT
        {{ test_id("cl._id") }}
    cl._id                        AS "UniqueId",
    k._id                         AS "KontraktId",
    CONCAT(cl.kontrakt_nummer, '.', UPPER(cl.firma))   AS "KontraktNummer",
    k.kundenummer                 AS "KundeNummer",
    k.byggnummer                  AS "ByggNummer",
    cl.leie_objekt_id             AS "ObjectId",
    cl.leie_objekt_navn           AS "RentalobjectName",
    LEFT(cl.navn, 50)                                   AS "ContractLineName",
    LEFT(cl.leie_kost_type_navn, 30)                    AS "RentalCosttypeName",
    LEFT(cl.areal_type_navn, 20)                        AS "AreaTypeName",
    COALESCE(cl.areal, 0)                               AS "Areal",
    COALESCE(cl.fysisk_areal, 0)                        AS "FysiskAreal",
    COALESCE(cl.areal_ikke_medregnet, 0)                AS "ArealIkkeMedregnet",
    CASE WHEN cl.leie_enhet = 'm2' THEN 0 ELSE COALESCE(cl.leie_antall, 0) END  AS "RentalQty",
    COALESCE(cl.leie_kost_gruppe_id, 0)                AS "CostGroupNum",
    COALESCE(cl.aarlig_beloep, 0)                       AS "Amount",
    cl.status_kode                                      AS "StatusKode",
    cl.status_navn                                      AS "StatusTekst",
    cl.gyldig_fra                                       AS "ValidFrom",
    cl.gyldig_til                                       AS "ValidTo",
    CASE
        WHEN k.byggnummer LIKE 'D%' THEN cl.FirstPossibleTerminationDate
        WHEN cl.status_kode <> 2 OR cl.leie_art_gruppe_n1 <> 'Leie' THEN NULL
        WHEN LOWER(cl.lopende) = 'ja' THEN NULL
        WHEN (COALESCE(cl.frist_oppsigelse_leietaker, '') = '') THEN cl.FirstPossibleTerminationDate
        ELSE cl.gyldig_til - (CAST(cl.frist_oppsigelse_leietaker AS INTEGER) * INTERVAL '1 month')
    END                                                 AS "FristOppsigelseLeietaker",
    CASE
        WHEN k.byggnummer LIKE 'D%' THEN cl.FirstPossibleTerminationDateLessor
        WHEN cl.status_kode <> 2 OR cl.leie_art_gruppe_n1 <> 'Leie' THEN NULL
        WHEN LOWER(cl.lopende) = 'ja' THEN NULL
        WHEN (COALESCE(cl.frist_oppsigelse_utleier, '') = '') THEN cl.FirstPossibleTerminationDateLessor
        ELSE cl.gyldig_til - (CAST(cl.frist_oppsigelse_utleier AS INTEGER) * INTERVAL '1 month')
    END                                                 AS "FristOppsigelseUtleier",
    cl.lokal_valuta                                     AS "LokalValuta",
    cl.unik_id                                          AS "KontraktLinjeNummer",
    '1970-01-01 00:00:00'::TIMESTAMP                    AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                    AS "LastUpdated"
FROM {{ ref('stg_d365_contract_line') }} cl
-- Resolve the ONE owning kontrakt (utleier) per line, mirroring Sesam's hops:
-- concat(kontrakt_nummer, '.', firma) = kontrakt unique_id. cl.firma is the utleier code;
-- joining on kontrakt_id alone fans out across every utleier variant of the kontrakt, which
-- duplicates UniqueId and lets the upsert land a non-deterministic ByggNummer/KundeNummer.
LEFT JOIN {{ ref('stg_d365_kontrakt') }} k
    ON LOWER(CONCAT(cl.kontrakt_nummer, '.', cl.firma)) = LOWER(k._id)
WHERE cl._id IS NOT NULL
  AND cl.unik_id IS NOT NULL
  AND k.kundenummer IS NOT NULL
  -- Sesam contract-details-kundeportal drops leie_kost_gruppe_id = 2 lines, keeps NULL.
  -- Verified read-only vs RW test: this single condition reproduces Sesam's row set exactly
  -- (18460 -> 9758 distinct UniqueId; the pipe's areal_type / leie_kost_type_id checks are
  --  offset by its IsRentalArea branch for D365 rows, so only this filter changes the set).
  AND (cl.leie_kost_gruppe_id IS NULL OR cl.leie_kost_gruppe_id <> 2)
