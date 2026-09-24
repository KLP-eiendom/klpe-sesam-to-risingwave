{{ config(
    materialized='materialized_view'
) }}

/*
  Materialized view for building data to Leko.
  Source for snk_bygg_leko and queried by RisingWave Data API.
*/

SELECT
    {{ test_id("COALESCE(bygg_id, bygg_avdeling_id)") }}
    COALESCE(bygg_id, bygg_avdeling_id)                                         AS "id",
    COALESCE(bygg_id, bygg_avdeling_id)                                         AS "number",
    COALESCE(b_bygg_type, ba_byggtype)                                           AS "type",
    b_navn                                                                       AS "departmentname",
    CASE
        WHEN LOWER(COALESCE(b_bygg_type, ba_byggtype)) IN ('kontor', 'handel')
        THEN bf_firma_navn
        ELSE COALESCE(fb_byggnavn, b_navn, ba_navn)
    END                                                                          AS "name",
    COALESCE(fb_adresse, b_adresse)                                              AS "address",
    b_by                                                                         AS "city",
    COALESCE(b_postnummer, bf_firma_postnummer)                                  AS "zipCode",
    b_by                                                                         AS "municipaly",
    "GnrBnr"                                                                     AS "parcelNumber",
    "bildearkivLink"                                                             AS "buildingImageUrl",
    "totAreal"                                                                   AS "totalAreal",
    andelfossilt                                                                 AS "fossilFuelShare",
    energiforbruk                                                                AS "energyConsumption",
    bf_firma_adresse || ', ' || bf_firma_postnummer || ' ' || bf_firma_sted      AS "postalAddress",
    bf_firma_adresse || ' NO-' || bf_firma_postnummer || ' ' || bf_firma_sted   AS "invoiceAddress",
    LOWER(COALESCE(ba_forvalter_epost, forvalter_epost, eiendomsansv))           AS "propertyManager",
    LOWER(COALESCE(ba_drift_epost, drift_epost, driftsansv))                     AS "operationManager",
    CASE
        WHEN LOWER(COALESCE(b_bygg_type, ba_byggtype)) IN ('kontor', 'handel')
        THEN bf_firma_navn
        ELSE b_navn
    END                                                                          AS "shoppingMall",
    bf_orgnummer                                                                 AS "organisationalNumber",
    bf_girokontonummer                                                           AS "accountNumber"

FROM {{ ref('mrt_global_property') }}
WHERE COALESCE(bygg_id, bygg_avdeling_id) IS NOT NULL
  AND b_firma_id IS NOT NULL
  AND b_firma_id != ''
  AND COALESCE(b_bygg_type, ba_byggtype) IN ('Handel', 'Kontor')
