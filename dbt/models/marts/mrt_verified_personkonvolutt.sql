{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam verified-personkonvolutt pipe.

  Flattens owners[] and recipients[] from stg_verified_envelope into
  individual person-per-envelope rows (emit_children pattern).

  Owner _id:       MD5(email || '_' || envelope_id || '_o')
  Recipient _id:   last path segment of recipient uid  (e.g. /recipients/abc → abc)

  Field name note: Verified REST API uses camelCase (givenName, familyName).
  If the payload uses snake_case (given_name, family_name) these will be NULL —
  adjust below if observed to be empty after first deploy.

  Dedup: the sink's target PK (MySQL PersonKonvolutt) is (PersonEpost, KonvoluttId, Type),
  which owners[]/recipients[] can violate two ways — confirmed against live data 2026-07-23:
    - Owners: the SAME entry (identical email+uid) repeated verbatim in owners[] — DISTINCT
      on the full row is enough, since _id is deterministic per (email, envelope_id).
    - Recipients: DIFFERENT recipient slots (different uid, e.g. a re-sent invite) sharing
      the same email in the same envelope — these have different _id, so a plain DISTINCT
      doesn't collapse them; need an explicit ROW_NUMBER pick per (email, envelope_id).
*/

WITH latest AS (
    -- PK upsert (latest-wins by envelope id) replaced the dedup CTE. A delete tombstone
    -- ({"_deleted": true}) overwrites the live row, so filter it out here.
    SELECT payload
    FROM {{ ref('stg_verified_envelope') }}
    WHERE NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
),

owners AS (
    SELECT DISTINCT
        MD5(LOWER(own->>'email') || '_' || (payload->>'id') || '_o')
                                                                    AS _id,
        LOWER(own->>'email')                                        AS email,
        own->>'givenName'                                           AS givenName,
        own->>'familyName'                                          AS familyName,
        payload->>'id'                                              AS envelopeId,
        'owner'                                                     AS type,
        (payload->>'created')::TIMESTAMPTZ                          AS createdAt,
        COALESCE((payload->>'created')::TIMESTAMPTZ::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
        COALESCE((payload->>'created')::TIMESTAMPTZ::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated"
    FROM latest,
    jsonb_array_elements(
        CASE WHEN jsonb_typeof(payload->'owners') = 'array' THEN payload->'owners' ELSE '[]'::JSONB END
    ) AS own
    WHERE own->>'email' IS NOT NULL
      AND own->>'email' != ''
),

recipients_raw AS (
    SELECT
        REGEXP_REPLACE(rec->>'uid', '^.*/', '')                     AS _id,
        LOWER(rec->>'email')                                        AS email,
        rec->>'givenName'                                           AS givenName,
        rec->>'familyName'                                          AS familyName,
        payload->>'id'                                              AS envelopeId,
        'recipient'                                                 AS type,
        (payload->>'created')::TIMESTAMPTZ                          AS createdAt,
        COALESCE((payload->>'created')::TIMESTAMPTZ::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
        COALESCE((payload->>'created')::TIMESTAMPTZ::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated",
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(rec->>'email'), payload->>'id'
            ORDER BY (rec->>'uid') ASC
        ) AS rn
    FROM latest,
    jsonb_array_elements(
        CASE WHEN jsonb_typeof(payload->'recipients') = 'array' THEN payload->'recipients' ELSE '[]'::JSONB END
    ) AS rec
    WHERE rec->>'email' IS NOT NULL
      AND rec->>'email' != ''
),

recipients AS (
    SELECT _id, email, givenName, familyName, envelopeId, type, createdAt, "Created", "LastUpdated"
    FROM recipients_raw
    WHERE rn = 1
)

SELECT * FROM owners
UNION ALL
SELECT * FROM recipients
