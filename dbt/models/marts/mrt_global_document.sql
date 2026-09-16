{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-document.

  Sesam merged three datasets:
    superoffice-document → stg_superoffice_document (webhook)
    verified-document    → mrt_verified_document (emit_children from stg_verified_envelope.documents[])
    leko-dokument        → derived from stg_leko_kontrakt via signedDocument fields

  Join key across all three: unique_verified_id
    SO:       concat(customFields.EnvelopeId, customFields.DocumentId)
              e.g. "HkxQKRmAbF" || "Syg4YRXCbt" → "HkxQKRmAbFSyg4YRXCbt"
    Verified: mrt_verified_document.unique_verified_id (uid with path segments stripped)
    Leko:     concat(signedDocument.envelopeUid, signedDocument.documentUid)

  SO drives; verified and leko enrich where matched.

  signed_date: MAX(doc->'signatures'[].date) via scalar subquery in mrt_verified_document.
    Falls back to SO createdDate in the sink when no verified signature is present.
    OpprettetAvSoPersonId    — requires lookup in mrt_global_user on owner email;
                               left as gap in sinks (owner email is exposed here).
    Filter: sinks should filter documenttemplatename LIKE 'Signert%'.
*/

WITH so_doc_raw AS (
    SELECT payload
    FROM {{ ref('stg_superoffice_document') }}
    WHERE (payload->>'documentId')::BIGINT IS NOT NULL
),

so_doc AS (
    SELECT
        (payload->>'documentId')::BIGINT                            AS documentId,
        payload->>'name'                                            AS name,
        payload->>'header'                                          AS header,
        payload->>'description'                                     AS description,
        (payload->>'createdDate')::TIMESTAMPTZ                      AS createdDate,
        (payload->>'updatedDate')::TIMESTAMPTZ                      AS updatedDate,
        payload->>'externalRef'                                     AS externalRef,
        (payload->'contact'->>'contactId')::BIGINT                  AS contactId,
        payload->'contact'->>'orgnr'                                AS contact_orgnr,
        (payload->'project'->>'projectId')::BIGINT                  AS projectId,
        payload->'project'->>'name'                                 AS projectName,
        payload->'project'->>'type'                                 AS project_type,
        (payload->'sale'->>'saleId')::BIGINT                        AS saleId,
        payload->'sale'->>'projectName'                             AS sale_project_name,
        (payload->'associate'->>'personId')::BIGINT                 AS created_by_person_id,
        payload->'associate'->>'fullName'                           AS created_by_name,
        payload->'createdBy'->>'fullName'                           AS created_by_full_name,
        (payload->'documentTemplate'->>'documentTemplateId')::BIGINT AS documentTemplateId,
        payload->'documentTemplate'->>'name'                        AS documentTemplateName,
        -- Sesam unique_verified_id: concat of Verified envelope + document GUIDs
        NULLIF(
            COALESCE(payload->'customFields'->>'EnvelopeId', payload->'customFields'->>'verifiedForSuperOffice:EnvelopeId', '') ||
            COALESCE(payload->'customFields'->>'DocumentId', payload->'customFields'->>'verifiedForSuperOffice:DocumentId', ''),
            ''
        )                                                           AS unique_verified_id,
        COALESCE(payload->'customFields'->>'EnvelopeId', payload->'customFields'->>'verifiedForSuperOffice:EnvelopeId') AS so_envelope_id
    FROM so_doc_raw
    WHERE NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
),

leko_doc_raw AS (
    -- Mirrors Sesam leko-dokument pipe: extracts signedDocument fields from leko-kontrakt
    SELECT
        id,
        payload
    FROM {{ ref('stg_leko_kontrakt') }}
    WHERE payload->'signedDocument'->>'documentUid' IS NOT NULL
      AND payload->'signedDocument'->>'documentUid' != ''
),

leko_doc_ranked AS (
    -- stg_leko_kontrakt is PK-upserted per contract id (no _row_id), but the join grain
    -- here is the envelope+document composite, which two contracts could share — keep
    -- one row per composite, picking the highest contract id deterministically.
    SELECT
        payload,
        ROW_NUMBER() OVER (
            PARTITION BY
                REPLACE(payload->'signedDocument'->>'envelopeUid', '/envelopes/', '') ||
                REPLACE(
                    payload->'signedDocument'->>'documentUid',
                    '/api' || (payload->'signedDocument'->>'envelopeUid') || '/documents/',
                    ''
                )
            ORDER BY id DESC
        ) AS rn
    FROM leko_doc_raw
),

leko_doc AS (
    -- Mirrors Sesam leko-dokument pipe: extracts signedDocument fields from leko-kontrakt
    SELECT
        payload->>'contractId'                                      AS leko_id,
        REPLACE(payload->'signedDocument'->>'envelopeUid', '/envelopes/', '') AS envelopeUid,
        REPLACE(
            payload->'signedDocument'->>'documentUid',
            '/api' || (payload->'signedDocument'->>'envelopeUid') || '/documents/',
            ''
        )                                                           AS documentUid,
        REPLACE(payload->'signedDocument'->>'envelopeUid', '/envelopes/', '') ||
        REPLACE(
            payload->'signedDocument'->>'documentUid',
            '/api' || (payload->'signedDocument'->>'envelopeUid') || '/documents/',
            ''
        )                                                           AS uniqueId
    FROM leko_doc_ranked
    WHERE rn = 1
)

SELECT
    so_doc.documentId,
    COALESCE(so_doc.name, vd.name)                                  AS name,
    so_doc.header,
    so_doc.description,
    GREATEST(so_doc.createdDate, vd.createdDate)                    AS createdDate,
    GREATEST(so_doc.updatedDate, vd.modifiedDate)                   AS updatedDate,
    COALESCE(GREATEST(so_doc.createdDate, vd.createdDate), '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    COALESCE(GREATEST(so_doc.updatedDate, vd.modifiedDate), '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated",
    so_doc.externalRef,
    so_doc.contactId,
    so_doc.contact_orgnr,
    so_doc.projectId,
    so_doc.projectName,
    so_doc.project_type,
    so_doc.saleId,
    so_doc.sale_project_name,
    so_doc.created_by_person_id,
    so_doc.created_by_name,
    so_doc.created_by_full_name,
    so_doc.documentTemplateId,
    so_doc.documentTemplateName,
    so_doc.unique_verified_id,
    so_doc.so_envelope_id,
    -- Verified document fields
    vd.uid                                                          AS verified_uid,
    vd.externalId                                                   AS verified_external_id,
    vd.owner,
    vd.envelope_id                                                  AS verified_envelope_id,
    vd.recipients                                                   AS verified_recipients,
    vd.signedAt                                                     AS signed_date,
    -- Leko fields
    leko_doc.envelopeUid                                            AS leko_envelope_uid,
    leko_doc.documentUid                                            AS leko_document_uid,
    leko_doc.leko_id

FROM so_doc
LEFT JOIN {{ ref('mrt_verified_document') }} AS vd
    ON so_doc.unique_verified_id = vd.unique_verified_id
    AND so_doc.unique_verified_id IS NOT NULL
LEFT JOIN leko_doc
    ON so_doc.unique_verified_id = leko_doc.uniqueId
    AND so_doc.unique_verified_id IS NOT NULL
