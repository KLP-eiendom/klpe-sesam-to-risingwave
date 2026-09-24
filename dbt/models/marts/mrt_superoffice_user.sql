{{ config(
    materialized='materialized_view'
) }}

WITH base AS (
    SELECT
        (payload->>'personId')::BIGINT                  AS personId,
        (payload->>'contactId')::BIGINT                 AS contactId,
        payload->>'email'                               AS email,
        payload->>'firstName'                           AS firstName,
        payload->>'lastName'                            AS lastName,
        payload->>'fullName'                            AS fullName_raw,
        payload->>'title'                               AS title,
        payload->>'mobilePhone'                         AS mobilePhone,
        payload->>'roleName'                            AS roleName,
        payload->>'region'                              AS region,
        payload->>'uniqueId'                            AS uniqueId,
        payload->>'copyEmail'                           AS copyEmail,
        COALESCE((payload->>'retired')::BOOLEAN, FALSE) AS retired,
        payload->'personInterestIds'                    AS personInterestIds,
        NULLIF(payload->>'personRegisteredDate', '')::TIMESTAMPTZ AS personRegisteredDate,
        NULLIF(payload->>'personUpdatedDate', '')::TIMESTAMPTZ    AS personUpdatedDate,
        NULLIF(REGEXP_REPLACE(payload->>'registered', '^~t', ''), '')::TIMESTAMPTZ AS registered,
        NULLIF(REGEXP_REPLACE(payload->>'updated',    '^~t', ''), '')::TIMESTAMPTZ AS updated,
        COALESCE((payload->>'deleted')::BOOLEAN, FALSE) AS deleted,
        COALESCE((payload->>'_deleted')::BOOLEAN, FALSE) AS _deleted
    FROM {{ ref('stg_superoffice_user') }}
    WHERE (payload->>'personId') IS NOT NULL
)

SELECT
    *,
    COALESCE(fullName_raw, firstName || ' ' || lastName) AS fullName
FROM base
