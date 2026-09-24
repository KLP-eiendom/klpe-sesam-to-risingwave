{{ config(materialized='materialized_view') }}

/*
  Unnests the comma-separated eiendnr field from stg_fdvweb_building into one
  row per eiendnr value, enabling an equality join from stg_d365_bygg_avdeling.

  RisingWave does not support nested-loop joins in streaming MVs, so
  ANY(STRING_TO_ARRAY(...)) cannot be used directly in mrt_global_property.
*/

SELECT
    _id,
    TRIM(u.eid) AS eiendnr
FROM {{ ref('stg_fdvweb_building') }},
    UNNEST(STRING_TO_ARRAY(eiendnr, ',')) AS u(eid)
