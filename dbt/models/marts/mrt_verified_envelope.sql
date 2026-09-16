{{ config(
    materialized='materialized_view'
) }}

SELECT
    payload->>'id'                           AS id,
    (payload->>'completed')::BOOLEAN         AS completed,
    (payload->>'aborted')::BOOLEAN           AS aborted,
    (payload->>'expired')::BOOLEAN           AS expired,
    (payload->>'published')::BOOLEAN         AS published,
    (payload->>'created')::TIMESTAMPTZ       AS created,
    (payload->>'modified')::TIMESTAMPTZ      AS modified,
    (payload->>'expiration')::TIMESTAMPTZ    AS expiration,
    (payload->>'publishDate')::TIMESTAMPTZ   AS publishDate,
    (payload->>'automaticReminders')::BIGINT AS automaticReminders,
    payload->>'descriptor'                   AS descriptor,
    payload->>'greeting'                     AS greeting,
    payload->'sender'->>'email'              AS sender_email
FROM {{ ref('stg_verified_envelope') }}
-- PK upsert (latest-wins by envelope id) replaced the dedup CTE. A delete tombstone
-- ({"_deleted": true}) overwrites the live row, so filter it out here.
WHERE NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
