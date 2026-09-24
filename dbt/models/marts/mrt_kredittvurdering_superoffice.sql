{{ config(
    materialized='materialized_view'
) }}

/*
  Replicates Sesam pipe 'kredittvurdering-superoffice'.
  Joins global-kredittvurdering with raw bisnode payload for finans/revisor fields,
  and bisnode-sanksjoner for sanction screening.

  Required fields for SuperOffice userdefined fields endpoint:
    ContactId, Dunsnr, Kredittrating, Soliditet, Betalingsanmerkning,
    MvaRegistrert, Revisor, RevisorKommentar, Underavvikling, Sanksjonert
*/

WITH so AS (
    SELECT
        contactId,
        nameDepartment,
        orgnr,
        stop,
        CASE
            WHEN orgnr IS NULL OR orgnr = ''
            THEN NULL
            ELSE REGEXP_REPLACE(orgnr, '[ \-]|MVA', '', 'g')
        END AS unique_orgnr
    FROM {{ ref('mrt_superoffice_contactsimple') }}
    WHERE contactId IS NOT NULL
      AND contactId > 0
),

bl_latest AS (
    -- Historical rows were double-encoded (payload as a JSON string); the unwrap handles
    -- both. PK upsert (latest-wins per orgnr) replaced the dedup CTE.
    SELECT (payload#>>'{}')::JSONB AS payload
    FROM {{ ref('stg_bisnode_leverandor') }}
),

bl_raw AS (
    SELECT
        -- Identity (new English format first, old Norwegian fallback)
        COALESCE(
            payload->'companyInformation'->'identifiers'->>'registrationNumber',
            payload->'companyInformation'->'identifiers'->>'vatNumber',
            payload->'identifikasjon'->>'orgnr'
        )                                                    AS orgnr,
        COALESCE(
            payload->'companyInformation'->'identifiers'->>'dunsNumber',
            payload->'identifikasjon'->>'dunsnr'
        )                                                    AS dunsnr,
        -- Rating / credit
        COALESCE(
            payload->'risk'->'creditRatings'->'currentCreditRating'->>'code',
            payload->'rating'->>'rating1'
        )                                                    AS kredittrating,
        -- Payment remarks
        COALESCE(
            payload->'risk'->'creditRatings'->'currentCreditRating'->'partJudgements'->'abilityToPay'->>'description',
            payload->'risk'->'creditRatings'->'currentCreditRating'->'partJudgements'->'historyOperation'->>'description',
            payload->'rating'->>'delbBetalingserfaring'
        )                                                    AS betalingsanmerkning,
        -- MVA
        CASE
            WHEN (payload->'companyInformation'->'generalCompanyData'->>'registeredInVat')::BOOLEAN = TRUE
              OR payload->'companyInformation'->'generalCompanyData'->>'activeInVat' = 'true'
            THEN 'ja'
            WHEN (payload->'companyInformation'->'generalCompanyData'->>'registeredInVat')::BOOLEAN = FALSE
            THEN 'nei'
            ELSE NULL
        END                                                  AS mvaRegistrert,
        -- Revisor — first current auditor (new format: elem.name; old format: elem.entity.name)
        (
            SELECT COALESCE(elem->>'name', elem->'entity'->>'name')
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(payload->'management'->'auditors'->'currentAuditors') = 'array'
                    THEN payload->'management'->'auditors'->'currentAuditors'
                    ELSE '[]'::jsonb
                END
            ) AS elem
            LIMIT 1
        )                                                    AS revisor,
        -- Auditor reservation description (concatenated)
        (
            SELECT STRING_AGG(elem->>'auditorsReservationDescription', ', ')
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(payload->'finance'->'financialStatements'->'auditorsReservations') = 'array'
                    THEN payload->'finance'->'financialStatements'->'auditorsReservations'
                    ELSE '[]'::jsonb
                END
            ) AS elem
        )                                                    AS revisorKommentar,
        -- Soliditet: equityAssetsRatio (%) from most recent financial year
        (
            SELECT COALESCE(
                (elem->>'equityAssetsRatio')::NUMERIC,
                (elem->>'egenkapitalandel')::NUMERIC
            )
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(payload->'finance'->'financialStatements'->'keyFigures') = 'array'
                    THEN payload->'finance'->'financialStatements'->'keyFigures'
                    ELSE '[]'::jsonb
                END
            ) AS elem
            WHERE elem->>'equityAssetsRatio' IS NOT NULL
               OR elem->>'egenkapitalandel' IS NOT NULL
            ORDER BY (elem->'closingPeriod'->>'year')::INT DESC NULLS LAST
            LIMIT 1
        )                                                    AS soliditet
    FROM bl_latest
),

bs_latest AS (
    -- Historical rows were double-encoded (payload as a JSON string); the unwrap handles
    -- both. PK upsert (latest-wins per normalized regno) replaced the dedup CTE.
    SELECT (payload#>>'{}')::JSONB AS payload
    FROM {{ ref('stg_bisnode_sanksjoner') }}
),

bs AS (
    SELECT
        -- Join via bisnode regNo (orgnr)
        LOWER(REGEXP_REPLACE(payload->'companyInput'->>'regNo', '[ \-]|MVA', '', 'g')) AS bs_orgnr,
        (payload->'screeningSummary'->>'noOfSanctionMatches')::INT      AS noOfSanctionMatches,
        (payload->'screeningSummary'->'obmsSummary'->>'withSanctionMatches')::INT AS withSanctionMatches
    FROM bs_latest
    WHERE payload->'screeningSummary'->>'noOfSanctionMatches' IS NOT NULL
)

SELECT
    so.contactId                                                                        AS "ContactId",
    bl.dunsnr                                                                           AS "Dunsnr",
    so.orgnr                                                                            AS "Orgnummer",
    bl.kredittrating                                                                    AS "Kredittrating",
    bl.betalingsanmerkning                                                              AS "Betalingsanmerkning",
    bl.soliditet                                                                        AS "Soliditet",
    bl.mvaRegistrert                                                                    AS "MvaRegistrert",
    bl.revisor                                                                          AS "Revisor",
    bl.revisorKommentar                                                                 AS "RevisorKommentar",
    CASE
        WHEN bs.noOfSanctionMatches IS NULL THEN NULL
        WHEN bs.noOfSanctionMatches > 0 OR COALESCE(bs.withSanctionMatches, 0) > 0 THEN TRUE
        ELSE FALSE
    END                                                                                 AS "Sanksjonert",
    FALSE                                                                               AS "Underavvikling"
    -- Note: Underavvikling comes from D365 (leverandorsperre/underAvvikling) which is not yet in RisingWave

FROM so
INNER JOIN bl_raw bl
    ON so.unique_orgnr = bl.orgnr::TEXT
LEFT JOIN bs
    ON LOWER(so.unique_orgnr) = bs.bs_orgnr
WHERE bl.dunsnr IS NOT NULL
