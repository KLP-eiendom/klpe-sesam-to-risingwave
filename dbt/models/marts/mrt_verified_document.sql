{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam verified-document pipe: emit_children on documents[]
  from stg_verified_envelope.

  Each envelope carries one or more signed documents. This model expands
  them into one row per document, pulling envelope-level context (owner,
  envelope_id, recipients, timestamps) onto each child row.

  unique_verified_id: uid with /envelopes/ and /documents/ path segments stripped,
  e.g. "/envelopes/HkxQKRmAbF/documents/Syg4YRXCbt" → "HkxQKRmAbFSyg4YRXCbt"
  This matches SO customFields.concat(EnvelopeId, DocumentId) and Sesam DTL:
    ["replace", {"/documents/": "", "/envelopes/": ""}, "_S.uid"]

  ExternalId: "<documentId>:verified-document" where documentId = part after /documents/
*/

WITH latest AS (
    -- PK upsert (latest-wins by envelope id) replaced the dedup CTE. A delete tombstone
    -- ({"_deleted": true}) overwrites the live row, so filter it out here.
    SELECT payload
    FROM {{ ref('stg_verified_envelope') }}
    WHERE NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
)

SELECT
    doc->>'uid'                                                 AS uid,
    REPLACE(REPLACE(doc->>'uid', '/documents/', ''), '/envelopes/', '')
                                                                AS unique_verified_id,
    -- Sesam ExternalId convention
    SPLIT_PART(doc->>'uid', '/documents/', 2) || ':verified-document'
                                                                AS externalId,
    -- Document-level fields
    doc->>'name'                                                AS name,
    -- Envelope-level context (from parent envelope row)
    payload->>'id'                                              AS envelope_id,
    LOWER(COALESCE(payload->>'owner', payload->'owners'->0->>'email')) AS owner,
    payload->'recipients'                                       AS recipients,
    -- Signatures: max signing date across all signatures on this document
    -- doc->'signatures' is an array of {date, email, status, ...} objects
    (SELECT MAX((sig->>'date')::TIMESTAMPTZ)
     FROM jsonb_array_elements(
         CASE WHEN jsonb_typeof(doc->'signatures') = 'array' THEN doc->'signatures' ELSE '[]'::JSONB END
     ) AS sig
    )                                                           AS signedAt,
    -- Timestamps: from parent envelope (Verified uses created/modified, not createdDate/updatedDate)
    (payload->>'created')::TIMESTAMPTZ                          AS createdDate,
    (payload->>'modified')::TIMESTAMPTZ                         AS modifiedDate
FROM latest,
jsonb_array_elements(
    CASE WHEN jsonb_typeof(payload->'documents') = 'array' THEN payload->'documents' ELSE '[]'::JSONB END
) AS doc
WHERE doc->>'uid' IS NOT NULL
  AND doc->>'uid' != ''
