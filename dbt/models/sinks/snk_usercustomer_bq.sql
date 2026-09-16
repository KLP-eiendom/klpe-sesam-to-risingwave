{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  BigQuery sink for user-customer mapping data.
  Mirrors Sesam usercustomer-bq → usercustomer-bq-rest-endpoint → bigquery-api.

  Source: mrt_global_user (joins stg_superoffice_user webhook + stg_superoffice_csuser for contactNumber).

  Maps SuperOffice users to their linked customer (company contact).

  Sesam fields: so_id, bruker_id, kunde_id, kundenummer
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("personId::VARCHAR || ':' || su_contactId::VARCHAR") }}
personId::VARCHAR       AS "so_id",
    bruker_id               AS "bruker_id",
    su_contactId::VARCHAR   AS "kunde_id",
    contactNumber::VARCHAR  AS "kundenummer"
FROM {{ ref('mrt_global_user') }}
WHERE personId IS NOT NULL
  AND personId != 0
  AND bruker_id LIKE '%@%.%'
  AND bruker_id NOT LIKE '%/%'
  AND NOT retired
  AND NOT _deleted
  -- Sesam usercustomer-bq: kunde_id = the USER-webhook side contactId only (not csuser's)
  AND su_contactId IS NOT NULL
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'bigquery',
    type = 'upsert',
    force_compaction = 'true',
    primary_key = 'so_id',
    bigquery.project = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    bigquery.dataset = 'KDI',
    bigquery.table = 'SuperOfficeBrukerKunde',
    bigquery.credentials = SECRET risingwave_gcp_sa
);
{% endif %}
