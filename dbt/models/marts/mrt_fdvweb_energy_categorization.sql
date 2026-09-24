{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam fdvweb-energy-categorization.
  Computes energy label and heating category per building.

  Source:
    stg_fdvweb_building  (eiendnr, energiforbruk, andelfossilt, energiskalaid, bygningskategori)
    fdvweb_helper_energy (seed — Enova grade thresholds per building category and scale)

  Fields:
    bygg_avdeling_id   — building identifier (eiendnr)
    EnergyUsage        — energy consumption in kWh/m² (energiforbruk)
    EnergyCategory     — energy letter grade A–G
    HeatingCategory    — heating category 1–5 based on fossil fuel percentage

  EnergyCategory logic (from Sesam fdvweb-energy-categorization DTL):
    1. Map bygningskategori → standardised BuildingCategoryName
       (same CASE as Sesam _buildingEnergyCategory)
    2. Look up lowest seed.value >= energiforbruk for
       matching (energiskalaid, BuildingCategoryName) → grade
    3. If energiforbruk > 0 but no threshold found → 'G' (fallback per Sesam)
    4. If energiforbruk = 0 or NULL → NULL (no energy reading)

  HeatingCategory thresholds (Sesam DTL case statement):
    andelfossilt <= 30   → '1'
    andelfossilt <= 47.5 → '2'
    andelfossilt <= 65   → '3'
    andelfossilt <= 82.5 → '4'
    andelfossilt >  82.5 → '5'
    andelfossilt = 0 / NULL → NULL (no fossil heating)
*/

WITH building_mapped AS (
    SELECT
        eiendnr,
        energiforbruk,
        andelfossilt,
        energiskalaid,
        CASE
            WHEN LOWER(bygningskategori) LIKE '%kontor%'   THEN 'Kontorbygning'
            WHEN LOWER(bygningskategori) LIKE '%forret%'   THEN 'Forretningsbygning'
            WHEN LOWER(bygningskategori) LIKE '%hotell%'   THEN 'Hotellbygning'
            WHEN LOWER(bygningskategori) LIKE '%industri%' THEN 'Lett industribygning, verksted'
            WHEN LOWER(bygningskategori) LIKE '%skole%'    THEN 'Skolebygning'
            WHEN LOWER(bygningskategori) LIKE '%barne%'    THEN 'Barnehage'
            WHEN LOWER(bygningskategori) LIKE '%kultur%'   THEN 'Kulturbygning'
            WHEN LOWER(bygningskategori) LIKE '%univ%'     THEN 'Universitets- og høgskolebygning'
            ELSE NULL
        END AS building_category
    FROM {{ ref('stg_fdvweb_building') }}
    WHERE eiendnr IS NOT NULL
),

grade_candidates AS (
    SELECT
        b.eiendnr,
        h.grade,
        ROW_NUMBER() OVER (
            PARTITION BY b.eiendnr
            ORDER BY h.value ASC
        )                                                   AS rn
    FROM building_mapped b
    JOIN {{ ref('fdvweb_helper_energy') }} h
        ON  h.energiskalaid       = b.energiskalaid
        AND h.buildingcategoryname = b.building_category
        AND h.value               >= b.energiforbruk
    WHERE b.energiforbruk > 0
      AND b.building_category IS NOT NULL
)

SELECT
    b.eiendnr                       AS bygg_avdeling_id,
    b.energiforbruk                 AS EnergyUsage,

    CASE
        WHEN b.energiforbruk IS NULL OR b.energiforbruk = 0 THEN NULL
        ELSE COALESCE(g.grade, 'G')
    END                             AS EnergyCategory,

    CASE
        WHEN b.andelfossilt IS NULL OR b.andelfossilt = 0 THEN NULL
        WHEN b.andelfossilt <= 30   THEN '1'
        WHEN b.andelfossilt <= 47.5 THEN '2'
        WHEN b.andelfossilt <= 65   THEN '3'
        WHEN b.andelfossilt <= 82.5 THEN '4'
        ELSE '5'
    END                             AS HeatingCategory

FROM building_mapped b
LEFT JOIN grade_candidates g
    ON  g.eiendnr = b.eiendnr
    AND g.rn = 1
WHERE b.energiforbruk > 0
   OR b.andelfossilt > 0
