{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-property + global-property-bq.
  Joins D365 property data with fdvweb building metadata.

  Source mapping (Sesam dataset → RisingWave):
    d365-bygg-avdeling    → stg_d365_bygg_avdeling   (canonical property key: bygg_avdeling_id)
    d365-building         → stg_d365_building          (building detail; bygg_id = bygg_avdeling_id)
    d365-grunneiendom     → stg_d365_grunneiendom      (land parcel; eiendom_id = bygg_avdeling_id)
    d365-bygg-firma       → stg_d365_bygg_firma         (firm ownership; bygg_id FK — one per building via bf_primary)
    fdvweb-building       → stg_fdvweb_building         (technical building data; eiendnr = bygg_avdeling_id)
    fdvweb-building-image → stg_fdvweb_building_image   (building images; byggNavnId FK — one per building via fbi_primary)

  Intermediate area models (mirrors Sesam d365-utleide/ledige/total-areal-grouped):
    mrt_d365_areal_grouped → adds TotalRentedArea, TotalVacantArea, TotalPhysicalArea

  Excluded:
    axapta-building

  Join keys (from Sesam global-property.conf.json):
    ba.bygg_avdeling_id = b.bygg_id
    ba.bygg_avdeling_id = g.eiendom_id  (deduplicated via g_primary)
    b.bygg_id           = bf.bygg_id    (deduplicated via bf_primary)
    ba.bygg_avdeling_id = fb.eiendnr    (deduplicated via fb_eid_primary — fdvweb eiendnr is comma-separated and unnested in stg_fdvweb_building_eiendnr)
    fb."byggNavnId"     = fbi."byggNavnId" (deduplicated via fbi_primary)
    ba.bygg_avdeling_id = ag.bygg_id

  Fan-out prevention:
    Four joins are guarded by deduplication CTEs that pick MIN(_id) per key.
    Without these, buildings with multiple firm records, land parcels, fdvweb
    eiendnr matches, or building images would appear as duplicate rows.

    CTE              Key           Source table
    ─────────────────────────────────────────────────────────────────────
    fb_eid_primary   eiendnr       stg_fdvweb_building_eiendnr  (unnested)
    bf_primary       bygg_id       stg_d365_bygg_firma
    fbi_primary      byggNavnId    stg_fdvweb_building_image
    g_primary        eiendom_id    stg_d365_grunneiendom
*/

WITH fb_eid_primary AS (
    -- One fdvweb _id per bygg_avdeling_id (guards against multiple fdvweb buildings sharing the same eiendnr after unnesting)
    SELECT eiendnr, MIN(_id) AS _id
    FROM {{ ref('stg_fdvweb_building_eiendnr') }}
    GROUP BY eiendnr
),

bf_primary AS (
    -- One firma record per bygg_id (buildings can have multiple ownership records)
    SELECT *
    FROM {{ ref('stg_d365_bygg_firma') }}
    WHERE _id IN (
        SELECT MIN(_id) FROM {{ ref('stg_d365_bygg_firma') }} GROUP BY bygg_id
    )
),

fbi_primary AS (
    -- One image per byggNavnId (case-insensitive dedup, matching Sesam lower() hop).
    -- MAX(_id) picks the last image alphabetically, mirroring Sesam's last-write-wins merge.
    -- Filters out base-path-only URLs (mirrors Sesam filter on empty fdvweb-image-basepath).
    SELECT *
    FROM {{ ref('stg_fdvweb_building_image') }}
    WHERE "bildearkivLink" IS NOT NULL
      AND "bildearkivLink" NOT LIKE '%/'
      AND _id IN (
        SELECT MAX(_id) FROM {{ ref('stg_fdvweb_building_image') }}
        WHERE "bildearkivLink" IS NOT NULL
          AND "bildearkivLink" NOT LIKE '%/'
        GROUP BY LOWER("byggNavnId")
    )
),

g_primary AS (
    -- One land parcel per eiendom_id
    SELECT *
    FROM {{ ref('stg_d365_grunneiendom') }}
    WHERE _id IN (
        SELECT MIN(_id) FROM {{ ref('stg_d365_grunneiendom') }} GROUP BY eiendom_id
    )
)

SELECT
    -- D365 bygg avdeling (canonical property identity).
    -- COALESCE so d365-building-only records (present in stg_d365_building but with no matching
    -- bygg-avdeling) still get a property key, mirroring Sesam global-property's merge:
    --   Id = coalesce(d365-building:bygg_id, d365-bygg-avdeling:bygg_avdeling_id).
    -- Avdeling-backed rows are unaffected (ba.bygg_avdeling_id is non-null → COALESCE is a no-op).
    COALESCE(ba.bygg_avdeling_id, b.bygg_id)     AS bygg_avdeling_id,
    COALESCE(ba.bygg_avdeling_id, b.bygg_id)     AS ba_bygg_id,
    -- TRUE for avdeling-backed rows; FALSE for d365-building-only records (no bygg-avdeling).
    -- Sesam's forvalter feed keys building-only by bygg_id (RW matches), but kundeportal/miljoprofil
    -- key them by BuildingId/BUILDINGID (not present in RW) — those sinks filter on this flag.
    (ba.bygg_avdeling_id IS NOT NULL)            AS has_avdeling,
    ba.bygg                 AS ba_navn,
    ba.eiendomtype          AS avdeling_type,
    ba.byggtype             AS ba_byggtype,
    ba.firma_id             AS ba_firma_id,
    ba.forvalter_epost      AS ba_forvalter_epost,
    ba.drift_epost          AS ba_drift_epost,

    -- D365 building
    b.bygg_id,
    b.bygg_navn             AS b_navn,
    b.adresse               AS b_adresse,
    b.postnummer            AS b_postnummer,
    b.sted                  AS b_by,
    b.kommune,
    b.fylke,
    b.byggeaar,
    b.bruksareal,
    b.eiendom_id,
    b.firma_id              AS b_firma_id,
    b.bygg_type             AS b_bygg_type,
    b.forvalter_epost,
    b.oekonomi_epost,
    b.drift_epost,

    -- D365 grunneiendom (land parcel)
    g.navn                  AS g_navn,
    g.adresse               AS g_adresse,
    g.postnummer            AS g_postnummer,
    g.by                    AS g_by,
    g.kommune               AS g_kommune,
    g.gnr,
    g.bnr,
    g.snr,
    g.areal                 AS g_areal,
    g.firma_id              AS g_firma_id,

    -- D365 bygg firma (firm ownership)
    bf.firma_id             AS bf_firma_id,
    bf.firma_navn           AS bf_firma_navn,
    bf.firma_adresse        AS bf_firma_adresse,
    bf.firma_postnummer     AS bf_firma_postnummer,
    bf.firma_sted           AS bf_firma_sted,
    bf.orgnummer            AS bf_orgnummer,
    bf.girokontonummer      AS bf_girokontonummer,
    bf.andel                AS bf_andel,
    bf.gyldig_fra           AS bf_fra_dato,
    bf.gyldig_til           AS bf_til_dato,

    -- fdvweb building (technical metadata)
    fb._id                  AS fb_id,
    fb."GABnr",
    fb."GnrBnr",
    fb.adresse              AS fb_adresse,
    fb."byggNavn"           AS fb_byggNavn,
    fb."byggNavnId"         AS fb_byggNavnId,
    fb.byggeaar             AS fb_byggeaar,
    fb.byggnr,
    fb.bygningskategori,
    fb.bygningsnavn,
    fb.eiendnr,
    fb."tomtAreal",
    fb."totAreal",
    fb."totEietAreal",
    fb."totLeietAreal",
    COALESCE(fb.energiforbruk, 0)                AS energiforbruk,
    fb.energiskalaid,
    fb.etasjer,
    fb.markedsomrade,
    fb.kompleksnr,
    fb.driftsansv,
    fb.driftsteknikker,
    fb.eiendomsansv,
    fb.eier,
    COALESCE(fb.andelfossilt, 0)                 AS andelfossilt,
    fb.arkitekt,
    fb.beliggenhet,
    fb.beskrivelse,
    fb.byggherre,
    fb.historikk,
    fb."oppvarmetAreal"         AS fb_oppvarmet_areal,

    -- fdvweb building images
    fbi._id                 AS fbi_id,
    fbi."bildearkivLink",
    fbi."bildearkivTekst",

    -- Area aggregations (mirrors Sesam d365-utleide/ledige/total-arealer-grouped)
    ag.utleid_areal                 AS TotalRentedArea,
    ag.ledig_areal                  AS TotalVacantArea,
    ag.total_areal                  AS TotalPhysicalArea,
    ag.markedspris_ledig_areal      AS MarketPriceVacantArea,

    -- timestamps
    b.gyldig_fra                    AS b_gyldig_fra,

    -- fdvweb energy categorization (mirrors Sesam fdvweb-energy-categorization)
    ec.energycategory                       AS "EnergyCategory"

-- FULL OUTER JOIN (was LEFT JOIN driven by bygg-avdeling): keeps d365-building-only records
-- (e.g. N20101, N25403) that have no bygg-avdeling row, matching Sesam global-property's merge.
-- Downstream enrichment joins key on COALESCE(ba.bygg_avdeling_id, b.bygg_id) so building-only
-- rows still match grunneiendom / fdvweb / areal / energy by their bygg_id.
FROM {{ ref('stg_d365_bygg_avdeling') }} ba
FULL OUTER JOIN {{ ref('stg_d365_building') }} b
    ON ba.bygg_avdeling_id = b.bygg_id
LEFT JOIN g_primary g
    ON COALESCE(ba.bygg_avdeling_id, b.bygg_id) = g.eiendom_id
LEFT JOIN bf_primary bf
    ON b.bygg_id = bf.bygg_id
LEFT JOIN fb_eid_primary fb_eid
    ON COALESCE(ba.bygg_avdeling_id, b.bygg_id) = fb_eid.eiendnr
LEFT JOIN {{ ref('stg_fdvweb_building') }} fb
    ON fb_eid._id = fb._id
LEFT JOIN fbi_primary fbi
    ON LOWER(fb."byggNavnId") = LOWER(fbi."byggNavnId")
LEFT JOIN {{ ref('mrt_d365_areal_grouped') }} ag
    ON COALESCE(ba.bygg_avdeling_id, b.bygg_id) = ag.bygg_id
LEFT JOIN {{ ref('mrt_fdvweb_energy_categorization') }} ec
    ON COALESCE(ba.bygg_avdeling_id, b.bygg_id) = ec.bygg_avdeling_id
