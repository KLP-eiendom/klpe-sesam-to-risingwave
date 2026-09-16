{{ config(
    materialized='materialized_view'
) }}

/*
  Materialized view for building drawings to Leko.
  Queried by RisingWave Data API (GET /api/v1/leko/byggtegning).
  Note: snk_byggtegning_leko and pubsub-writer worker were removed because Leko
  does not implement a REST push sync endpoint for files (api/klp-file/sessam/sync).
  In Sesam this was similarly exposed only as a pull http_endpoint.
*/

WITH property_matches AS (
    SELECT
        fb_byggNavnId,
        ARRAY_AGG(bygg_avdeling_id)                                     AS building_ids,
        BOOL_OR(ba_byggtype = 'Handel')                                 AS is_handel,
        BOOL_OR(ba_byggtype = 'Kontor')                                 AS is_kontor
    FROM {{ ref('mrt_global_property') }}
    WHERE fb_byggNavnId IS NOT NULL
    GROUP BY fb_byggNavnId
),

prepared AS (
    SELECT
        bt.UniqueId                                                     AS "id",
        bt.Created                                                      AS "created",
        bt.Navn                                                         AS "name",
        bt.BucketFilnavn                                                AS "path",
        bt.Type                                                         AS "type",
        p.building_ids                                                  AS "buildingIds",
        CASE
            WHEN p.is_handel AND p.is_kontor THEN 'Handel,Kontor'
            WHEN p.is_kontor THEN 'Kontor'
            WHEN p.is_handel THEN 'Handel'
            ELSE ''
        END                                                             AS "buildingType",
        p.is_handel,
        p.is_kontor,
        bt.Fag
    FROM {{ ref('stg_kundeportal_byggtegning') }} bt
    LEFT JOIN property_matches p ON bt.FdvWebByggId = p.fb_byggNavnId
)

SELECT
    {{ test_id("prepare.id::VARCHAR") }}
    "id",
    "created",
    "name",
    "path",
    "type",
    "buildingIds",
    "buildingType"
FROM prepared prepare
WHERE Fag = 'Kontraktsvedlegg'
  AND (is_handel OR is_kontor)
