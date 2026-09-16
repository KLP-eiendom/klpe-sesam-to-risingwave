{{ config(
    materialized='materialized_view',
    tags=['mart', 'leko']
) }}

/*
  Materialized view for contract data to Leko.
  Source for snk_kontrakt_leko.
  Streams Leko contract webhook events.
*/

SELECT
    {{ test_id("payload->>'id'") }}
    payload
FROM {{ ref('stg_leko_kontrakt') }}
