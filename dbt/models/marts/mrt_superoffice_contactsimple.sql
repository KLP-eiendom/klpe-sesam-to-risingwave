{{ config(
    materialized='materialized_view'
) }}

SELECT
    (payload->>'contactId')::BIGINT         AS contactId,
    payload->>'name'                        AS name,
    payload->>'nameDepartment'              AS nameDepartment,
    payload->>'contactPhoneFormattedNumber' AS contactPhoneFormattedNumber,
    payload->>'emailAddress'                AS emailAddress,
    payload->>'city'                        AS city,
    payload->>'country'                     AS country,
    payload->>'category'                    AS category,
    payload->>'business'                    AS business,
    payload->>'code'                        AS code,
    payload->>'number'                      AS number,
    payload->>'orgnr'                       AS orgnr,
    (payload->>'stop')::BOOLEAN             AS stop,
    payload->>'registeredBy'                AS registeredBy,
    (payload->>'registeredDate')::TIMESTAMPTZ AS registeredDate,
    payload->>'updatedBy'                   AS updatedBy,
    (payload->>'updatedDate')::TIMESTAMPTZ  AS updatedDate,
    payload->>'url'                         AS url,
    payload->>'department'                  AS department,
    payload->>'description'                 AS description,
    payload->>'invoiceAddress'              AS invoiceAddress,
    (payload->'address'->'street'->>'formatted')  AS streetAddress,
    (payload->'address'->'postal'->>'formatted')  AS postalAddress,
    (payload->>'isOwnerContact')::BOOLEAN   AS isOwnerContact,
    payload->'interests'                    AS interests
FROM {{ ref('stg_superoffice_contactsimple') }}
WHERE (payload->>'contactId') IS NOT NULL
  AND NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
