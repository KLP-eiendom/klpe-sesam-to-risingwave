{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-envelope.
  Single source: mrt_verified_envelope (Verified.eu webhook, JSONB parsed).
*/

SELECT * FROM {{ ref('mrt_verified_envelope') }}
