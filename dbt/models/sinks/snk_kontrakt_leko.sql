{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for mrt_leko_kontrakt.
  Mirrors Sesam kontrakt-leko-kdi → leko-kdipubsub.

  Streams Leko contract webhook events to the topic in real-time.
  A downstream consumer reads from the topic and POSTs to the Leko KDI API.
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
FROM {{ ref('mrt_leko_kontrakt') }}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_LEKO_KONTRAKT", "leko-contract-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'id',
    snapshot = false   -- HINDRET HISTORISK BACKFILL
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% else %}
SELECT * FROM {{ ref('mrt_leko_kontrakt') }}
{% endif %}
