{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for Project Juridisk Selskap to SuperOffice.
  Mirrors Sesam prosjekt-juridiskselskap-superoffice-rest-endpoint.

  Source: mrt_superoffice_project_juridiskselskap.
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
    {{ test_id("projectId::VARCHAR") }}
    projectId                                                           AS "ProjectId",
    "projectType"                                                       AS "Type",
    navn                                                                AS "Navn",
    orgnummer                                                           AS "Orgnummer",
    gaardbruksnummer                                                    AS "Gaardbruksnummer",
    adresse                                                             AS "Adresse"
FROM {{ ref('mrt_superoffice_project_juridiskselskap') }}

{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_PROSJEKT_JURIDISK_SELSKAP", "prosjekt-juridiskselskap-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'projectId'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
