{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink']
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  Pub/Sub sink for building data destined for KLP Findable (Firestore `buildings` collection).
  Format is JSON, and the KlpeFindable API acts as the worker consuming this topic via a push subscription.

  Expected fields in Findable:
  - id: string
  - name: string
  - address: string
  - category: string
  - gnr: string (optional)
  - bnr: string (optional)
  - municipality: string (optional)
  - owner: string (optional)
  - forvalter: string (optional) — D365 forvalter_epost
  - okonomiansvarlig: string (optional) — D365 oekonomi_epost
  - driftssjef: string (optional) — D365 drift_epost (fallback: FDVweb driftsansv)
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("COALESCE(bygg_id, ba_bygg_id, bygg_avdeling_id)::VARCHAR") }}
COALESCE(bygg_id, ba_bygg_id, bygg_avdeling_id) AS "id",
    COALESCE(b_navn, g_navn, fb_byggNavn, bygningsnavn) AS "name",
    COALESCE(b_adresse, g_adresse, fb_adresse) AS "address",
    bygningskategori AS "category",
    gnr AS "gnr",
    bnr AS "bnr",
    COALESCE(kommune, g_kommune) AS "municipality",
    eier AS "owner",
    forvalter_epost AS "forvalter",
    oekonomi_epost AS "okonomiansvarlig",
    COALESCE(drift_epost, driftsansv) AS "driftssjef",
    energiforbruk::DECIMAL                       AS "EnergiForbruk",
    andelfossilt::DECIMAL                        AS "AndelFossilEl"
FROM {{ ref('mrt_global_property') }}
WHERE bygg_avdeling_id IS NOT NULL
  AND LENGTH(COALESCE(bygg_id, ba_bygg_id, bygg_avdeling_id)) >= 6
  AND COALESCE(b_navn, g_navn, fb_byggNavn, bygningsnavn) IS NOT NULL

{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = 'klpe-findable-building-sync',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.message_key = 'id'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
