{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  BigQuery sink for building energy/classification data.
  Mirrors Sesam bygg-bqeos → bygg-bqeos-rest-endpoint → bigquery-api.

  Source: mrt_global_property.

  Sesam fields: ByggId, Navn, AndelFossilt, Energiforbruk, Energikategori,
                OppvarmetAreal, FdvWebId, Oppvarmingskategori, Byggeaar

*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("COALESCE(bygg_id, bygg_avdeling_id)") }}
COALESCE(bygg_id, bygg_avdeling_id)         AS "ByggId",
    COALESCE(b_navn, ba_navn, fb_byggnavn)       AS "Navn",
    andelfossilt::DECIMAL                        AS "AndelFossilt",
    energiforbruk::DECIMAL                       AS "Energiforbruk",
    fb_byggnavnid                                AS "FdvWebId",
    fb_byggeaar                                  AS "Byggeaar",
    energycategory                               AS "Energikategori",
    fb_oppvarmet_areal::DECIMAL                  AS "OppvarmetAreal",
    heatingcategory::VARCHAR                     AS "Oppvarmingskategori"
FROM {{ ref('mrt_bygg_forvalter') }}
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'bigquery',
    type = 'upsert',
    force_compaction = 'true',
    primary_key = 'ByggId',
    bigquery.project = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    bigquery.dataset = 'EOS_MeterData',
    bigquery.table = 'ByggInfo',
    bigquery.credentials = SECRET risingwave_gcp_sa
);
{% endif %}
