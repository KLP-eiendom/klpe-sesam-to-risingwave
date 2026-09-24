{{ config(
    materialized='materialized_view'
) }}

-- NOTE: Bisnode webhook double-encodes the body; unwrap once before extracting fields.
WITH p AS (
    SELECT (payload#>>'{}')::JSONB AS payload
    FROM {{ ref('stg_bisnode_sanksjoner') }}
)

SELECT
    payload->>'bisnodeReference'               AS bisnodeReference,
    payload->'companyInput'->>'name'           AS companyName,
    payload->'companyInput'->>'regNo'          AS regNo,
    payload->'companyInput'->>'nationality'    AS nationality,
    (payload->>'nameMatchLevel')::BIGINT       AS nameMatchLevel,
    (payload->>'isIndirectOwner')::BOOLEAN     AS isIndirectOwner,
    payload->>'message'                        AS message,
    payload->>'dateFormat'                     AS dateFormat
FROM p
