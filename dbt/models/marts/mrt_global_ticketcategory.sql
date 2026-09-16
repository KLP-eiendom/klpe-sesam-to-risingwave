{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-ticketcategory + ticketcategory-kundeportal.
  Merges SuperOffice property categories, SuperOffice support categories,
  and Kundeportal Sakskategori metadata into a unified category list.

  Source mapping (Sesam dataset → RisingWave):
    superoffice-ticketcategory  → stg_superoffice_ticketcategory  (type="property")
    superoffice-supportcategory → stg_superoffice_supportcategory (type="support")
    kundeportal-ticketcategory  → stg_kundeportal_ticketcategory  (MySQL CDC, Sakskategori)

  Merge key (Sesam used namespace identifiers; here we join on (SakskategoriId, System, Type)):
    so_property: ticketCategoryId, system="superoffice", type="property"
    so_support:  id,               system="superoffice", type="support"
    kundeportal: joined on (SakskategoriId, System, Type)

  Sesam ticketcategory-kundeportal DTL logic applied here:
    Navn          = COALESCE(so_property.name, REPLACE(so_support.name, "option=", ""), kp.Navn)
    SakskategoriId= COALESCE(so_property.ticketCategoryId, so_support.id)
    Parent        = COALESCE(so_property.parentId, kp.Parent, -1)
    System        = 'superoffice' (hardcoded in both SO sources)
    Type          = 'property' | 'support'
    Kode          = kp.Kode
    Created       = kp.Created (set on first write)
    Updated       = TRUE when SO name differs from KP Navn (name changed in SO since last sync)

  Note: Verify the KDI gateway path for stg_superoffice_supportcategory
  (currently configured as superoffice/supportcategory/items).
  Sesam used "&includeId=sakunderkategoriSync" on the direct SuperOffice system.
*/

WITH so_property AS (
    SELECT
        ticketCategoryId                                AS SakskategoriId,
        name                                            AS so_navn,
        COALESCE(parentId, -1)                          AS Parent,
        'superoffice'::VARCHAR                          AS System,
        'property'::VARCHAR                             AS Type,
        fullname
    FROM {{ ref('stg_superoffice_ticketcategory') }}
),

so_support AS (
    SELECT
        id                                              AS SakskategoriId,
        REPLACE(name, 'option=', '')                    AS so_navn,
        -1                                              AS Parent,
        'superoffice'::VARCHAR                          AS System,
        'support'::VARCHAR                              AS Type,
        NULL::VARCHAR                                   AS fullname
    FROM {{ ref('stg_superoffice_supportcategory') }}
),

all_so AS (
    SELECT * FROM so_property
    UNION ALL
    SELECT * FROM so_support
),

kp AS (
    SELECT
        id                  AS id,
        sakskategoriid      AS kp_id,
        system              AS kp_system,
        type                AS kp_type,
        navn                AS kp_navn,
        kode                AS kp_kode,
        created             AS kp_created,
        lastupdated         AS kp_last_updated
    FROM {{ ref('stg_kundeportal_ticketcategory') }}
    WHERE system = 'superoffice'
)

SELECT
    so.SakskategoriId,
    COALESCE(so.so_navn, kp.kp_navn)                    AS Navn,
    so.Parent,
    so.System,
    so.Type,
    kp.kp_kode                                          AS Kode,
    COALESCE(kp.kp_created, '1970-01-01 00:00:00'::TIMESTAMP)      AS Created,
    COALESCE(kp.kp_last_updated, '1970-01-01 00:00:00'::TIMESTAMP) AS LastUpdated,
    so.fullname,
    kp.id                                               AS "Id",

    -- Updated flag: TRUE when SO name has changed vs what Kundeportal has stored.
    -- NOTE: Kundeportal `Sakskategori` has NO `Updated` column (KundeportalCommonDAL EF snapshot),
    -- so snk_ticketcategory_kundeportal does NOT emit this — it's computed-but-unused. The Sesam
    -- ticketcategory-kundeportal dataset carries `Updated`, but it never reaches the destination;
    -- it's blacklisted in snk_ticketcategory_kundeportal.test.json so Tier-2 doesn't false-flag it.
    CASE
        WHEN kp.kp_navn IS NOT NULL
         AND kp.kp_navn != so.so_navn
         AND so.so_navn IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END                                                  AS Updated

FROM all_so so
LEFT JOIN kp
    ON  so.SakskategoriId = kp.kp_id
    AND so.System         = kp.kp_system
    AND so.Type           = kp.kp_type
