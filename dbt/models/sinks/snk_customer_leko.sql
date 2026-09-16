{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for customer data to Leko.
  Mirrors Sesam customer-leko → leko REST API (post-company operation).

  Source: mrt_global_customer — SuperOffice contact fields used as company identity.
  Sesam used the SO contact as the company record sent to Leko (not the D365 customer).

  A downstream consumer reads from the topic and POSTs to the Leko company endpoint.
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT * FROM {{ ref('mrt_customer_leko') }}
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_CUSTOMER_LEKO", "customer-leko-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'Id'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
