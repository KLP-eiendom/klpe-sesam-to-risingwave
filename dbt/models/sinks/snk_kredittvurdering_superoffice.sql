{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for mrt_kredittvurdering_superoffice.
  Streams credit assessment changes to the topic in real-time.

  A downstream consumer (Azure Function / Cloud Run) reads from the topic
  and POSTs to the SuperOffice REST API:
    POST {eiendom-api-url}/kdi/superoffice/contact/userdefinedfields
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id('"ContactId"') }}
"ContactId",
    "Dunsnr",
    "Orgnummer",
    "Kredittrating",
    "Betalingsanmerkning" AS "Betanmerkning",
    "Soliditet",
    "MvaRegistrert",
    "Revisor",
    "RevisorKommentar",
    "Underavvikling",
    "Sanksjonert"
FROM {{ ref('mrt_kredittvurdering_superoffice') }}
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_KREDITTVURDERING", "kredittvurdering-superoffice-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'ContactId'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
