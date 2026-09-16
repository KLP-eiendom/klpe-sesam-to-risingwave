{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-leverandorvurdering + leverandorvurdering-bq.
  Joins SuperOffice vendor contacts with Bisnode credit data, D365 vendor data,
  and Bisnode sanctions screening.

  Source mapping (Sesam dataset → RisingWave):
    superoffice-contactsimple-leverandor → mrt_superoffice_contactsimple
      (Sesam filtered SO contacts to vendors via custom fields 15/16.
       In RisingWave the INNER JOIN on bisnode orgnr achieves equivalent filtering —
       only contacts matched to a Bisnode record appear in the output.)
    bisnode-leverandor                   → stg_bisnode_leverandor  (raw JSONB)
    d365-leverandor                      → stg_d365_leverandor
    bisnode-sanksjoner                   → stg_bisnode_sanksjoner

  Known gaps vs Sesam:
    Okonomiskforhold_sistvurdert — D365 last financial assessment timestamp (not in BQ dim_leverandor)
*/

WITH so_raw AS (
    -- Query stg directly to access both basic fields and custom fields in one CTE,
    -- avoiding a self-join multiplication that would occur if we joined marts + stg.
    SELECT payload
    FROM {{ ref('stg_superoffice_contactsimple') }}
    WHERE (payload->>'contactId')::BIGINT IS NOT NULL
      AND (payload->>'contactId')::BIGINT > 0
),

so_clean AS (
    SELECT
        (payload->>'contactId')::BIGINT                   AS contactId,
        payload->>'nameDepartment'                         AS nameDepartment,
        payload->>'orgnr'                                  AS orgnr,
        payload->>'emailAddress'                           AS emailAddress,
        payload->>'city'                                   AS city,
        payload->>'country'                                AS country,
        (payload->>'stop')::BOOLEAN                        AS stop,
        payload->>'registeredBy'                           AS registeredBy,
        NULLIF(payload->>'registeredDate', '')::TIMESTAMPTZ  AS registeredDate,
        payload->>'updatedBy'                              AS updatedBy,
        NULLIF(payload->>'updatedDate', '')::TIMESTAMPTZ   AS updatedDate,
        CASE
            WHEN payload->>'orgnr' IS NULL OR payload->>'orgnr' = ''
            THEN CONCAT('uuid-', (payload->>'contactId'))
            ELSE REGEXP_REPLACE(payload->>'orgnr', '[ \-]|MVA', '', 'g')
        END                                                AS unique_orgnr,
        payload->>'businessName'                           AS bransje_so,
        -- Guard userDefinedFields against JSON null (RisingWave throws on null::jsonb->>'key')
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:15', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:15', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'15') AS udf_15,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:16', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:16', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'16') AS udf_16,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:17', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:17', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'17') AS udf_17,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:18', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:18', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'18') AS udf_18,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:19', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:19', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'19') AS udf_19,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:20', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:20', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'20') AS udf_20,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:26', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:26', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'26') AS udf_26,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:27', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:27', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'27') AS udf_27,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:28', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:28', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'28') AS udf_28,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:29', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:29', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'29') AS udf_29,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:32', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:32', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'32') AS udf_32,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:33', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:33', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'33') AS udf_33,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:34', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:34', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'34') AS udf_34,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:35', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:35', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'35') AS udf_35,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:36', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:36', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'36') AS udf_36,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:47', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:47', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'47') AS udf_47,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:48', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:48', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'48') AS udf_48,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:8:DisplayText', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:8:DisplayText', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'8:DisplayText') AS udf_8_dt,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:16:DisplayText', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:16:DisplayText', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'16:DisplayText') AS udf_16_dt,
        COALESCE(NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:47:DisplayText', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:47:DisplayText', NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'47:DisplayText') AS udf_47_dt
    FROM so_raw
    WHERE NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
),

so_prepared AS (
    SELECT
        contactId,
        nameDepartment,
        orgnr,
        emailAddress,
        city,
        country,
        stop,
        registeredBy,
        registeredDate,
        updatedBy,
        updatedDate,
        unique_orgnr,
        bransje_so,
        NULLIF(REGEXP_REPLACE(COALESCE(udf_16, ''), '[^0-9]', '', 'g'), '')       AS klassifiseringkode,
        udf_17                                                            AS unntak,
        udf_18                                                            AS bransje,
        udf_19                                                            AS rammeavtale,
        udf_20                                                            AS evalueringskommentar,
        udf_27                                                            AS miljodokumentasjon,
        udf_28                                                            AS samfunnsansvar,
        udf_29                                                            AS innmeldtav,
        udf_32                                                            AS eu,
        udf_33                                                            AS adm,
        udf_34                                                            AS sf,
        udf_35                                                            AS dv,
        udf_36                                                            AS fo,
        NULLIF(REGEXP_REPLACE(COALESCE(udf_47, ''), '[^0-9]', '', 'g'), '')       AS manuellsanksjonsjekkkode,
        udf_48                                                            AS manuellsanksjonsjekkkommentar,
        REGEXP_REPLACE(udf_8_dt, '^NO:"|";$', '', 'g')                    AS lokasjon,
        REGEXP_REPLACE(udf_16_dt, '^NO:"|";$', '', 'g')                          AS klassifiseringbeskrivelse,
        udf_47_dt                                                         AS manuellsanksjonsjekkbeskrivelse,
        -- udf_26 arrives as SuperOffice's raw CRMScript date wrapper, e.g. "[D:01/26/2022 00:01:00.0000000]"
        -- or "[D:01/01/0001 00:00:00.0000000]" when unset — strip the wrapper, reorder MM/DD/YYYY to
        -- ISO YYYY-MM-DD so RisingWave's str_to_timestamptz accepts it, then null out the unset sentinel.
        NULLIF(
            NULLIF(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(udf_26, '^\[D:|\]$', '', 'g'),
                    '^(\d{2})/(\d{2})/(\d{4}) ', '\3-\1-\2 '
                ),
                ''
            )::TIMESTAMPTZ,
            '0001-01-01 00:00:00+00'::TIMESTAMPTZ
        )                                                                  AS driftsforhold_sistvurdert,
        CASE
            WHEN NULLIF(REGEXP_REPLACE(COALESCE(udf_15, ''), '[^0-9]', '', 'g'), '') IS NULL
              OR NULLIF(REGEXP_REPLACE(COALESCE(udf_15, ''), '[^0-9]', '', 'g'), '') = '0'
            THEN CONCAT('uuid-', contactId::TEXT)
            ELSE NULLIF(REGEXP_REPLACE(COALESCE(udf_15, ''), '[^0-9]', '', 'g'), '')
        END                                                               AS d365_leverandornummer
    FROM so_clean
    WHERE (
        (
            REGEXP_REPLACE(COALESCE(udf_15, ''), '[^0-9]', '', 'g') != ''
            AND REGEXP_REPLACE(COALESCE(udf_15, ''), '[^0-9]', '', 'g') != '0'
        )
        OR (
            udf_16 IS NOT NULL
            AND udf_16 != '[I:0]'
            AND orgnr IS NOT NULL
            AND orgnr != ''
        )
    )
),

so AS (
    SELECT
        contactId,
        nameDepartment,
        orgnr,
        emailAddress,
        city,
        country,
        stop,
        registeredBy,
        registeredDate,
        updatedBy,
        updatedDate,
        unique_orgnr,
        bransje_so,
        klassifiseringkode,
        unntak,
        bransje,
        rammeavtale,
        evalueringskommentar,
        miljodokumentasjon,
        samfunnsansvar,
        innmeldtav,
        eu,
        adm,
        sf,
        dv,
        fo,
        manuellsanksjonsjekkkode,
        manuellsanksjonsjekkkommentar,
        lokasjon,
        klassifiseringbeskrivelse,
        manuellsanksjonsjekkbeskrivelse,
        driftsforhold_sistvurdert,
        d365_leverandornummer,
        ROW_NUMBER() OVER (
            PARTITION BY d365_leverandornummer
            ORDER BY contactId DESC
        ) AS vendor_rn
    FROM so_prepared
),

bl_latest AS (
    -- Historical rows were double-encoded (payload as a JSON string); the unwrap handles
    -- both. PK upsert (latest-wins per orgnr) replaced the dedup CTE.
    SELECT (payload#>>'{}')::JSONB AS payload
    FROM {{ ref('stg_bisnode_leverandor') }}
),

bl AS (
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

        -- Credit rating
        COALESCE(
            payload->'risk'->'creditRatings'->'currentCreditRating'->>'code',
            payload->'rating'->>'rating1'
        )                                                    AS kredittrating,

        -- Payment remarks (Betalingsanmerkning — note Sesam had typo "Betanmerkning")
        COALESCE(
            payload->'risk'->'creditRatings'->'currentCreditRating'->'partJudgements'->'abilityToPay'->>'description',
            payload->'risk'->'creditRatings'->'currentCreditRating'->'partJudgements'->'historyOperation'->>'description',
            payload->'rating'->>'delbBetalingserfaring'
        )                                                    AS betalingsanmerkning,

        -- MVA registration
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

        -- Auditor reservations (concatenated)
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
        )                                                    AS soliditet,

        -- Aarsregnskap: last closed financial year as "YYYY-M"
        (
            SELECT CONCAT(
                elem->'closingPeriod'->>'year', '-',
                elem->'closingPeriod'->>'month'
            )
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(payload->'finance'->'financialStatements'->'keyFigures') = 'array'
                    THEN payload->'finance'->'financialStatements'->'keyFigures'
                    ELSE '[]'::jsonb
                END
            ) AS elem
            WHERE elem->'closingPeriod'->>'year' IS NOT NULL
            ORDER BY
                (elem->'closingPeriod'->>'year')::INT  DESC NULLS LAST,
                (elem->'closingPeriod'->>'month')::INT DESC NULLS LAST
            LIMIT 1
        )                                                    AS aarsregnskap,

        -- Okonomiskforhold_sistvurdert: date of most recent credit rating from Bisnode
        CASE
            WHEN payload->'risk'->'creditRatings'->'currentCreditRating'->'date'->>'year' IS NOT NULL
            THEN MAKE_DATE(
                (payload->'risk'->'creditRatings'->'currentCreditRating'->'date'->>'year')::INT,
                (payload->'risk'->'creditRatings'->'currentCreditRating'->'date'->>'month')::INT,
                COALESCE(
                    (payload->'risk'->'creditRatings'->'currentCreditRating'->'date'->>'day')::INT,
                    1
                )
            )::TIMESTAMPTZ
            ELSE NULL
        END                                                  AS bl_okonomiskforhold_sistvurdert,

        -- Company name fallback (for Navn when D365 and SO names are absent)
        COALESCE(
            payload->'companyInformation'->'companyName'->'registeredName'->>'name',
            payload->'navnAdresse'->>'navn'
        )                                                    AS bl_navn,

        -- Industry codes
        COALESCE(
            payload->'companyInformation'->'industryCodeSet'->'sni2007IndustryCodes'->'primaryIndustryCode'->>'code',
            payload->'companyInformation'->'industryCodeSet'->'naceCodes'->'primaryNaceCode'->>'code',
            payload->'companyInformation'->'industryCodeSet'->'sicCodes'->0->>'code'
        )                                                    AS industrikode,
        COALESCE(
            payload->'companyInformation'->'industryCodeSet'->'sni2007IndustryCodes'->'primaryIndustryCode'->>'description',
            payload->'companyInformation'->'industryCodeSet'->'naceCodes'->'primaryNaceCode'->>'description',
            payload->'companyInformation'->'industryCodeSet'->'sicCodes'->0->>'primarySicCode'
        )                                                    AS industrikode_beskrivelse

    FROM bl_latest
),

dl AS (
    SELECT
        leverandor_id,
        REGEXP_REPLACE(COALESCE(organisasjonsnummer, ''), '[ \-]', '', 'g') AS clean_orgnr,
        navn                                        AS d365_navn,
        aktiv                                       AS d365_aktiv,
        leverandorsperre,
        merknad,
        underavvikling,
        undertvangsavviklingellertvangsopplosning,
        leverandorgruppe
    FROM {{ ref('stg_d365_leverandor') }}
),

bs_latest AS (
    -- Historical rows were double-encoded (payload as a JSON string); the unwrap handles
    -- both. PK upsert (latest-wins per normalized regno) replaced the dedup CTE.
    SELECT (payload#>>'{}')::JSONB AS payload
    FROM {{ ref('stg_bisnode_sanksjoner') }}
),

bs AS (
    SELECT
        LOWER(REGEXP_REPLACE(payload->'companyInput'->>'regNo', '[ \-]|MVA', '', 'g')) AS bs_orgnr,
        (payload->'screeningSummary'->>'noOfSanctionMatches')::INT      AS noOfSanctionMatches,
        (payload->'screeningSummary'->'obmsSummary'->>'withSanctionMatches')::INT AS withSanctionMatches
    FROM bs_latest
    WHERE payload->'screeningSummary'->>'noOfSanctionMatches' IS NOT NULL
)

SELECT
    -- SuperOffice identity
    so.contactId,
    so.nameDepartment,
    so.orgnr,
    so.unique_orgnr,
    so.emailAddress,
    so.city,
    so.country,
    so.stop,
    so.registeredBy,
    so.registeredDate,
    so.updatedBy,
    so.updatedDate,

    -- Bisnode credit fields
    bl.dunsnr,
    bl.kredittrating,
    bl.betalingsanmerkning,
    bl.mvaRegistrert,
    bl.revisor,
    bl.revisorKommentar,
    bl.soliditet,
    bl.aarsregnskap,

    -- D365 vendor fields
    dl.leverandor_id                                                                    AS d365_leverandor_id,
    dl.d365_navn,
    dl.d365_aktiv,
    (dl.leverandorsperre IS NOT NULL AND dl.leverandorsperre != 0)                     AS sperret,
    dl.merknad                                                                         AS d365kommentar,
    bl.bl_okonomiskforhold_sistvurdert                                                 AS okonomiskforhold_sistvurdert,

    -- Sanctions screening
    CASE
        WHEN bs.noOfSanctionMatches IS NULL THEN NULL
        WHEN bs.noOfSanctionMatches > 0 OR COALESCE(bs.withSanctionMatches, 0) > 0 THEN TRUE
        ELSE FALSE
    END                                                                                 AS sanksjonert,

    (dl.underavvikling = 'ja' OR dl.undertvangsavviklingellertvangsopplosning = 'ja')  AS underavvikling,
    (dl.leverandorgruppe = '200')                                                       AS konsernintern,

    -- Bisnode industry codes
    bl.industrikode,
    bl.industrikode_beskrivelse,

    -- Vendor name (D365 → SO → Bisnode)
    COALESCE(dl.d365_navn, so.nameDepartment, bl.bl_navn)   AS navn,

    -- SO custom fields (from raw contactsimple payload)
    so.bransje_so,
    so.klassifiseringkode,
    so.klassifiseringbeskrivelse,
    so.unntak,
    so.bransje,
    so.rammeavtale,
    so.evalueringskommentar,
    so.miljodokumentasjon,
    so.samfunnsansvar,
    so.innmeldtav,
    so.eu,
    so.adm,
    so.sf,
    so.dv,
    so.fo,
    so.manuellsanksjonsjekkkode,
    so.manuellsanksjonsjekkbeskrivelse,
    so.manuellsanksjonsjekkkommentar,
    so.lokasjon,
    so.driftsforhold_sistvurdert

FROM so
LEFT JOIN bl
    ON so.unique_orgnr = bl.orgnr::TEXT
LEFT JOIN dl
    ON so.d365_leverandornummer = dl.leverandor_id
LEFT JOIN bs
    ON LOWER(so.unique_orgnr) = bs.bs_orgnr
WHERE so.d365_leverandornummer IS NOT NULL
  AND so.vendor_rn = 1
