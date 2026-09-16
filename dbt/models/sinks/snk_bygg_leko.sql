{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for property data to Leko.
  Mirrors Sesam bygg-leko → leko REST API (post-building operation).

  Source: mrt_bygg_leko.

  A downstream consumer reads from the topic and POSTs to the Leko building endpoint.

  Gap vs Sesam:
    name / shoppingMall (Handel/Kontor) — Sesam resolves parent company via prefix-based
      hop on firma_id (N2→N101, S→S100, D→D100, N5→N151). Using bf_firma_navn (direct
      ownership firm) as approximation.
    municipaly — mapped from building.sted/by (Sesam used region).
    postalAddress / invoiceAddress — NULL when bygg_firma address fields are missing.
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT * FROM {{ ref('mrt_bygg_leko') }}
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_BYGG_LEKO", "bygg-leko-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'id'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
