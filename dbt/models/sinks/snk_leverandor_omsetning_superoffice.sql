{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for vendor turnover data to SuperOffice.
  Mirrors Sesam leverandor-omsetning-superoffice-rest-endpoint.

  Streams vendor annual turnover to the topic in real-time.
  A downstream consumer (Azure Function / Cloud Run) reads from the topic
  and POSTs to the SuperOffice REST API:
    POST {eiendom-api-url}/kdi/superoffice/contact/userdefinedfields
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("ContactId") }}
leverandornummer,
    omsetning_belop_i_aar,
    omsetning_belop_i_fjor,
    contactId,
    "MvaRegistrert",
    "Revisor",
    "Sperret",
    "D365Kommentar",
    "UnderAvvikling",
    "Engangsleverandor",
    "Konsernintern"
FROM {{ ref('mrt_leverandor_omsetning_superoffice') }}
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_LEVERANDOR_OMSETNING", "leverandor-omsetning-superoffice-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'contactId'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
