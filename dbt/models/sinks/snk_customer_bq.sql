{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  BigQuery sink for customer data.
  Mirrors Sesam customer-bq → BigQuery REST endpoint (post-customer operation).

  Source: mrt_global_customer.

  Sesam fields: Id, Nummer, Navn, GateAdresse, PostNummer, Poststed, Epost, Kundegruppe, Land, SuperOfficeContactId
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("contactId::VARCHAR") }}
contactId::VARCHAR                                  AS "Id",
    kundenummer                                         AS "Nummer",
    navn                                                AS "Navn",
    COALESCE(gate_adresse, adresse)                     AS "GateAdresse",
    postnummer                                          AS "PostNummer",
    COALESCE(city, by)                                  AS "Poststed",
    COALESCE(emailAddress, kontakt_epost)               AS "Epost",
    kundegruppe                                         AS "Kundegruppe",
    country                                             AS "Land",
    contactId::VARCHAR                                  AS "SuperOfficeContactId"
FROM {{ ref('mrt_global_customer') }}
WHERE kundenummer IS NOT NULL
  AND (category IS NULL OR category NOT LIKE '%Utgått%')
  AND contactId IS NOT NULL
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'bigquery',
    type = 'upsert',
    force_compaction = 'true',
    primary_key = 'Id',
    bigquery.project = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    bigquery.dataset = 'KDI',
    bigquery.table = 'SuperOfficeKunde',
    bigquery.credentials = SECRET risingwave_gcp_sa
);
{% endif %}
