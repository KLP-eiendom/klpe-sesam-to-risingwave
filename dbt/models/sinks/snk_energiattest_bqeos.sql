{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  BigQuery sink for building energy attestation data.
  Mirrors Sesam energiattest-bqeos → energiattest-bqeos-rest-endpoint → bigquery-api.

  Source: mrt_global_property.

  Sesam fields: ByggNummer, AndelFossilEl, EnergiForbruk, EnergiKarakter, Navn
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("COALESCE(bygg_id, bygg_avdeling_id)") }}
bygg_avdeling_id                     AS "ByggNummer",
    COALESCE(andelfossilt, 0)::DECIMAL   AS "AndelFossilEl",
    COALESCE(energiforbruk, 0)::DECIMAL  AS "EnergiForbruk",
    b_navn                               AS "Navn",
    "EnergyCategory"::VARCHAR            AS "EnergiKarakter"
FROM {{ ref('mrt_global_property') }}
-- Sesam energiattest-bqeos filters ONLY on ByggNummer IS NOT NULL; EnergiKarakter is a plain
-- coalesce that may be null. Do NOT drop rows with a null EnergyCategory — that under-produces
-- vs Sesam (the null grade is the documented fdvweb energy-grade gap, a value gap, not a row gap).
WHERE bygg_avdeling_id IS NOT NULL
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'bigquery',
    type = 'upsert',
    force_compaction = 'true',
    primary_key = 'ByggNummer',
    bigquery.project = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    bigquery.dataset = 'EOS_MeterData',
    bigquery.table = 'EnergiAttest',
    bigquery.credentials = SECRET risingwave_gcp_sa
);
{% endif %}
