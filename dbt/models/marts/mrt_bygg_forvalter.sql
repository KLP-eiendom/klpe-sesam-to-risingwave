{{ config(
    materialized='materialized_view'
) }}

/*
  Enriches mrt_global_property with Region (from stg_d365_firma)
  and energy classification (from mrt_fdvweb_energy_categorization).
  Used by snk_bygg_forvalter.

  Joins:
    stg_d365_firma           ON ba_firma_id = firma_id     → region
    mrt_fdvweb_energy_categorization ON bygg_avdeling_id   → energycategory, heatingcategory
*/

SELECT
    p.*,
    f.region,
    ec.energycategory,
    ec.heatingcategory,
    COALESCE(p.b_gyldig_fra::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    COALESCE(p.b_gyldig_fra::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated"
FROM {{ ref('mrt_global_property') }} p
LEFT JOIN {{ ref('stg_d365_firma') }} f
    ON p.ba_firma_id = f.firma_id
LEFT JOIN {{ ref('mrt_fdvweb_energy_categorization') }} ec
    ON p.bygg_avdeling_id = ec.bygg_avdeling_id
