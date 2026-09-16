{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam d365-utleide-areal + d365-ledige-arealer + d365-total-arealer-grouped,
  collapsed into one per-building aggregation.

  Sesam computed these as three separate intermediate datasets keyed by unique_eiendom_id,
  then merged them into global-property. Here we compute all three columns in a single pass.

  Source:
    stg_d365_areas   (bygg_id, kontrakt_id, fysisk_areal, ledig_areal, markedspris_ledig_areal)

  Fields:
    total_areal              — total physical area across all area records
    utleid_areal             — rented area (kontrakt_id is NOT the vacant placeholder '-')
    ledig_areal              — market-listed vacant area (dedicated BQ column)
    markedspris_ledig_areal  — market price of vacant area (dedicated BQ column)
*/

SELECT
    bygg_id,
    SUM(fysisk_areal)                                                   AS total_areal,
    SUM(CASE WHEN kontrakt_id != '-' THEN fysisk_areal ELSE 0 END)     AS utleid_areal,
    SUM(COALESCE(ledig_areal, 0))                                       AS ledig_areal,
    SUM(COALESCE(markedspris_ledig_areal, 0))                           AS markedspris_ledig_areal

FROM {{ ref('stg_d365_areas') }}
WHERE bygg_id IS NOT NULL
GROUP BY bygg_id
