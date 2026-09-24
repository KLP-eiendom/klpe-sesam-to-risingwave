{{ config(
    materialized='materialized_view'
) }}

/*
  Global credit assessment view — mirrors the Sesam pipe 'global-kredittvurdering'.
  Merges three sources by:
    1. superoffice-contactsimple → cleaned orgnr (spaces, dashes, "MVA" stripped)
    2. bisnode-leverandor joined on orgnr
    3. bisnode-sanksjoner joined on bisnode dunsnr → verifiedCompany.dunsNo
*/

WITH so_cleaned AS (
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
        -- Replicate Sesam DTL: strip spaces, dashes, and the suffix "MVA"
        -- If orgnr is empty, use NULL (won't join to bisnode, equivalent to Sesam's UUID fallback)
        CASE
            WHEN orgnr IS NULL OR orgnr = ''
            THEN NULL
            ELSE REGEXP_REPLACE(orgnr, '[ \-]|MVA', '', 'g')
        END AS unique_orgnr
    FROM {{ ref('mrt_superoffice_contactsimple') }}
),

bl AS (
    SELECT
        orgnr,
        dunsnr,
        navn                AS bl_navn,
        gateAdresse         AS bl_gateAdresse,
        gatePostnr          AS bl_gatePostnr,
        gatePoststed        AS bl_gatePoststed,
        etablertAr,
        selskFormKode,
        selskFormTekst,
        registrertMVA,
        rating1,
        ratingBeskrivelse,
        ratingLimit
    FROM {{ ref('mrt_bisnode_leverandor') }}
),

bs_raw AS (
    -- Bisnode sanksjoner sender double-encodes the body as a JSON string;
    -- unwrap once before extracting fields.
    SELECT (payload#>>'{}')::JSONB AS payload
    FROM {{ ref('stg_bisnode_sanksjoner') }}
),

bs AS (
    SELECT
        payload->>'bisnodeReference'                    AS bisnodeReference,
        payload->'companyInput'->>'name'               AS bs_companyName,
        payload->'companyInput'->>'regNo'              AS bs_regNo,
        (payload->>'nameMatchLevel')::BIGINT           AS nameMatchLevel,
        (payload->>'isIndirectOwner')::BOOLEAN         AS isIndirectOwner,
        payload->>'message'                             AS bs_message,
        -- Join key: verifiedCompany.dunsNo matches bisnode-leverandor dunsnr
        payload->'verifiedCompany'->>'dunsNo'          AS verified_dunsNo
    FROM bs_raw
)

SELECT
    -- SuperOffice identity
    so.contactId,
    so.nameDepartment,
    so.orgnr                    AS so_orgnr,
    so.unique_orgnr,
    so.emailAddress,
    so.city,
    so.country,
    so.stop,
    so.registeredBy,
    so.registeredDate,

    -- Bisnode Leverandør (company registry)
    bl.orgnr                    AS bl_orgnr,
    bl.dunsnr,
    bl.bl_navn,
    bl.bl_gateAdresse,
    bl.bl_gatePostnr,
    bl.bl_gatePoststed,
    bl.etablertAr,
    bl.selskFormKode,
    bl.selskFormTekst,
    bl.registrertMVA,
    bl.rating1,
    bl.ratingBeskrivelse,
    bl.ratingLimit,

    -- Bisnode Sanksjoner (sanctions check)
    bs.bisnodeReference,
    bs.bs_companyName,
    bs.bs_regNo,
    bs.nameMatchLevel,
    bs.isIndirectOwner,
    bs.bs_message

FROM so_cleaned so
LEFT JOIN bl
    ON so.unique_orgnr = bl.orgnr::TEXT
LEFT JOIN bs
    ON bl.dunsnr::TEXT = bs.verified_dunsNo
