{{ config(
    materialized='materialized_view'
) }}

SELECT
    (payload->>'documentId')::BIGINT        AS documentId,
    payload->>'name'                        AS name,
    payload->>'header'                      AS header,
    payload->>'description'                 AS description,
    payload->>'externalRef'                 AS externalRef,
    payload->>'ourRef'                      AS ourRef,
    payload->>'yourRef'                     AS yourRef,
    payload->>'attention'                   AS attention,
    (payload->>'createdDate')::TIMESTAMPTZ  AS createdDate,
    (payload->>'updatedDate')::TIMESTAMPTZ  AS updatedDate,
    (payload->'contact'->>'contactId')::BIGINT AS contactId,
    (payload->'project'->>'projectId')::BIGINT AS projectId,
    payload->'project'->>'name'             AS projectName,
    (payload->'documentTemplate'->>'documentTemplateId')::BIGINT AS documentTemplateId,
    payload->'documentTemplate'->>'name'    AS documentTemplateName
FROM {{ ref('stg_superoffice_document') }}
WHERE (payload->>'documentId') IS NOT NULL
  AND NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
