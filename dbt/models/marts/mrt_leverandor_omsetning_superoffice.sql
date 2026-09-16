{{ config(
    materialized='materialized_view'
) }}

/*
  Vendor turnover view for SuperOffice. Mirrors Sesam d365-leverandor-omsetning-grouped
  + leverandor-omsetning-superoffice-rest.

  Feeds snk_leverandor_omsetning_superoffice → SuperOffice user-defined fields endpoint:
    POST {eiendom-api-url}/kdi/superoffice/contact/userdefinedfields

  Aggregates stg_d365_leverandoromsetning by leverandor (sum per current and prior year),
  joins with stg_d365_leverandor for vendor flags, and mrt_global_leverandorvurdering
  for SuperOffice contactId and Bisnode-derived fields (Revisor, MvaRegistrert).

  Only vendors with a matched SuperOffice contactId are emitted (filter mirrors Sesam).

  Gap vs Sesam:
    Konsernintern — maps leverandorgruppe = "200"; other groups are not Konsernintern
*/

WITH omsetning AS (
    -- BigQuery pre-aggregates current and prior year turnover per vendor
    SELECT
        leverandor_id,
        COALESCE(omsetning_belop_i_aar, 0)  AS omsetning_belop_i_aar,
        COALESCE(omsetning_belop_i_fjor, 0) AS omsetning_belop_i_fjor
    FROM {{ ref('stg_d365_leverandoromsetning') }}
),

lev AS (
    SELECT
        leverandor_id,
        aktiv,
        leverandorsperre,
        merknad,
        underavvikling,
        undertvangsavviklingellertvangsopplosning,
        engangsleverandor,
        leverandorgruppe
    FROM {{ ref('stg_d365_leverandor') }}
),

lv AS (
    SELECT DISTINCT ON (d365_leverandor_id)
        d365_leverandor_id,
        contactId,
        mvaRegistrert,
        revisor
    FROM {{ ref('mrt_global_leverandorvurdering') }}
    WHERE d365_leverandor_id IS NOT NULL
)

SELECT
    o.leverandor_id                             AS leverandornummer,
    ROUND(o.omsetning_belop_i_aar::NUMERIC)     AS omsetning_belop_i_aar,
    ROUND(o.omsetning_belop_i_fjor::NUMERIC)    AS omsetning_belop_i_fjor,
    lv.contactId,
    lv.mvaRegistrert                            AS "MvaRegistrert",
    lv.revisor                                  AS "Revisor",

    (lev.leverandorsperre IS NOT NULL AND lev.leverandorsperre != 0)                        AS "Sperret",
    lev.merknad                                                                              AS "D365Kommentar",
    (lev.underavvikling = 'ja' OR lev.undertvangsavviklingellertvangsopplosning = 'ja')     AS "UnderAvvikling",
    (lev.engangsleverandor = 'ja')                                                           AS "Engangsleverandor",
    (lev.leverandorgruppe = '200')                                                           AS "Konsernintern"

FROM omsetning o
LEFT JOIN lev ON o.leverandor_id = lev.leverandor_id
LEFT JOIN lv  ON o.leverandor_id = lv.d365_leverandor_id
WHERE lv.contactId IS NOT NULL
