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
  Google Pub/Sub sink for customer lease data to SuperOffice.
  Mirrors Sesam kunde-leie-superoffice-rest-endpoint.

  A downstream consumer reads from the subscription and POSTs to:
    POST {eiendom-api-url}/kdi/superoffice/contact/userDefinedFields

  Source: mrt_d365_kunde_kontrakt_leie.
  Sesam payload fields: kundenummer, updatedDate, kundeAarsinntekt, kundeLeieareal
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
WITH countable_area AS (
    SELECT
            kontrakt_nummer,
        SUM(CASE
            WHEN areal_ikke_medregnet = 0
             AND leie_kost_gruppe_id = 1
             AND antall = 0
            THEN COALESCE(areal, 0)::DOUBLE PRECISION ELSE 0
        END) AS medregnet_areal
    FROM {{ ref('stg_d365_contract_line') }}
    WHERE _is_active = true OR gyldig_til IS NULL
    GROUP BY kontrakt_nummer
),

active_contracts AS (
    SELECT
        k.kundenummer                        AS kundenummer,
        SUM(k.leie)                          AS total_leie,
        SUM(COALESCE(ca.medregnet_areal, 0)) AS total_leieareal
    FROM {{ ref('stg_d365_kontrakt') }} k
    LEFT JOIN countable_area ca ON k.kontrakt_id = ca.kontrakt_nummer
    WHERE k.kundenummer IS NOT NULL
    GROUP BY k.kundenummer
),

so_updated AS (
    SELECT contactId, updatedDate
    FROM {{ ref('mrt_superoffice_contactsimple') }}
    WHERE contactId IS NOT NULL
)

SELECT
    {{ test_id("k.kundenummer") }}
    k.kundenummer,
    so.updatedDate                                          AS "updatedDate",
    ROUND(COALESCE(ac.total_leie, 0)::NUMERIC, 2)          AS "kundeAarsinntekt",
    ROUND(COALESCE(ac.total_leieareal, 0)::NUMERIC, 2)     AS "kundeLeieareal"
FROM {{ ref('stg_d365_kunde') }} k
LEFT JOIN active_contracts ac
    ON k.kundenummer = ac.kundenummer
LEFT JOIN {{ ref('mrt_global_customer') }} gc
    ON k.kundenummer = gc.kundenummer
LEFT JOIN so_updated so
    ON gc.contactId = so.contactId
WHERE k.kundenummer IS NOT NULL

{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_KUNDE_LEIE", "kunde-leie-superoffice-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'kundenummer'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
