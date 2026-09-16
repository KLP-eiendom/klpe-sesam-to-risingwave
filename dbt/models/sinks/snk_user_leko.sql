{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for SuperOffice users to Leko.
  Mirrors Sesam user-leko → leko REST API (post-user operation).

  Source: mrt_superoffice_user (SO user webhook).
  Sesam filtered to users where companyId (contactId) is not null.

  A downstream consumer reads from the topic and POSTs to the Leko user endpoint.

*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT * FROM {{ ref('mrt_user_leko') }}
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_USER_LEKO", "user-leko-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'id'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
