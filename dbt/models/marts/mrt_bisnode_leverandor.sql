{{ config(
    materialized='materialized_view'
) }}

-- The Bisnode webhook migrated from a Norwegian-keyed API format to the English
-- camelCase Bisnode Global API format.  COALESCE on every field handles rows in
-- either format that may coexist in the staging table.
--
-- NOTE: historical rows were double-encoded (payload as a JSON string); the unwrap
-- CTE handles both string-encoded and object payloads. PK upsert (latest-wins per
-- orgnr) replaced the dedup CTE.

WITH latest AS (
    SELECT (payload#>>'{}')::JSONB AS payload
    FROM {{ ref('stg_bisnode_leverandor') }}
)

SELECT
    -- Text, not numeric: Bisnode Global API registrationNumber/vatNumber are free-text and not
    -- always purely numeric (see Identifiers.cs — both are string, unlike the legacy int Orgnr).
    COALESCE(
        payload->'companyInformation'->'identifiers'->>'registrationNumber',
        payload->'companyInformation'->'identifiers'->>'vatNumber',
        payload->'identifikasjon'->>'orgnr'
    )                                                               AS orgnr,
    COALESCE(
        (payload->'companyInformation'->'identifiers'->>'dunsNumber')::BIGINT,
        (payload->'identifikasjon'->>'dunsnr')::BIGINT
    )                                                               AS dunsnr,
    COALESCE(
        payload->'companyInformation'->'companyName'->'registeredName'->>'name',
        payload->'navnAdresse'->>'navn'
    )                                                               AS navn,
    COALESCE(
        payload->'companyInformation'->'contactPoints'->'registeredAddress'->'streetAddress'->>'street',
        payload->'navnAdresse'->>'gateAdresse'
    )                                                               AS gateAdresse,
    COALESCE(
        (payload->'companyInformation'->'contactPoints'->'registeredAddress'->'streetAddress'->>'postalCode')::BIGINT,
        (payload->'navnAdresse'->>'gatePostnr')::BIGINT
    )                                                               AS gatePostnr,
    COALESCE(
        payload->'companyInformation'->'contactPoints'->'registeredAddress'->'streetAddress'->>'town',
        payload->'navnAdresse'->>'gatePoststed'
    )                                                               AS gatePoststed,
    COALESCE(
        payload->'companyInformation'->'status'->>'value',
        payload->'navnAdresse'->>'kodeType'
    )                                                               AS kodeType,
    COALESCE(
        payload->'companyInformation'->'legalForm'->'current'->>'description',
        payload->'companyInformation'->'legalForm'->>'description',
        payload->'navnAdresse'->>'kodeTekst'
    )                                                               AS kodeTekst,
    COALESCE(
        payload->'companyInformation'->'contactPoints'->'electronicContactPoints'->'phoneNumbers'->0->>'fullNumber',
        payload->'navnAdresse'->>'telefon'
    )                                                               AS telefon,
    COALESCE(
        (payload->'companyInformation'->'registrationInformation'->'foundationDate'->>'year')::BIGINT,
        (payload->'grunnfakta'->>'etablertAr')::BIGINT
    )                                                               AS etablertAr,
    COALESCE(
        CASE
            WHEN payload->'companyInformation'->'registrationInformation'->'registrationDate'->>'year' IS NOT NULL
            THEN MAKE_DATE(
                (payload->'companyInformation'->'registrationInformation'->'registrationDate'->>'year')::INT,
                COALESCE((payload->'companyInformation'->'registrationInformation'->'registrationDate'->>'month')::INT, 1),
                COALESCE((payload->'companyInformation'->'registrationInformation'->'registrationDate'->>'day')::INT, 1)
            )::TEXT
            ELSE NULL
        END,
        payload->'grunnfakta'->>'registrertDato'
    )                                                               AS registrertDato,
    COALESCE(
        payload->'companyInformation'->'legalForm'->'current'->>'code',
        payload->'companyInformation'->'legalForm'->>'localCode',
        payload->'grunnfakta'->>'selskFormKode'
    )                                                               AS selskFormKode,
    COALESCE(
        payload->'companyInformation'->'legalForm'->'current'->>'description',
        payload->'companyInformation'->'legalForm'->>'description',
        payload->'grunnfakta'->>'selskFormTekst'
    )                                                               AS selskFormTekst,
    COALESCE(
        (payload->'companyInformation'->'generalCompanyData'->>'registeredInVat')::BOOLEAN,
        (payload->'companyInformation'->'generalCompanyData'->>'activeInVat')::BOOLEAN,
        (payload->'grunnfakta'->>'registrertMVA')::BOOLEAN
    )                                                               AS registrertMVA,
    COALESCE(
        payload->'risk'->'creditRatings'->'currentCreditRating'->>'code',
        payload->'rating'->>'rating1'
    )                                                               AS rating1,
    COALESCE(
        payload->'risk'->'creditRatings'->'currentCreditRating'->>'description',
        payload->'rating'->>'ratingBeskrivelse'
    )                                                               AS ratingBeskrivelse,
    COALESCE(
        (payload->'risk'->'ratingCreditLimits'->'currentRatingCreditLimit'->'amount'->>'amount')::BIGINT,
        (payload->'rating'->>'limit')::BIGINT
    )                                                               AS ratingLimit
FROM latest
