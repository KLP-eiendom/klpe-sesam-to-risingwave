{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-purring.
  Single source: stg_d365_purring_detaljer (D365 dunning/reminder details).
*/

SELECT 
    *,
    '1970-01-01 00:00:00'::TIMESTAMP AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP AS "LastUpdated"
FROM {{ ref('stg_d365_purring_detaljer') }}
