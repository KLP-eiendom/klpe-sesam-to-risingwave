{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for mrt_leverandorvurdering_superoffice.
  Streams vendor assessment changes to the topic in real-time.

  A downstream consumer (Azure Function / Cloud Run) reads from the topic
  and POSTs to the SuperOffice REST API:
    POST {eiendom-api-url}/kdi/superoffice/contact/userdefinedfields

  All fields are now populated from mrt_leverandorvurdering_superoffice.
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("contactId") }}
contactId                    AS "ContactId",
    dunsnr                       AS "Dunsnr",
    orgnr                        AS "Orgnummer",
    kredittrating                AS "Kredittrating",
    betalingsanmerkning          AS "Betanmerkning",
    soliditet                    AS "Soliditet",
    aarsregnskap                 AS "Aarsregnskap",
    okonomiskforhold_sistvurdert AS "Okonomiskforhold",
    mvaRegistrert                AS "MvaRegistrert",
    sperret                      AS "Sperret",
    d365Kommentar                AS "D365Kommentar",
    revisor                      AS "Revisor",
    revisorKommentar             AS "RevisorKommentar",
    sanksjonert                  AS "Sanksjonert",
    underavvikling               AS "Underavvikling",
    konsernintern                AS "Konsernintern"
FROM {{ ref('mrt_global_leverandorvurdering') }}
-- The historical Sesam pipe (leverandorvurdering-superoffice-rest.conf.json) filtered on
-- `neq null ContactId AND neq null Dunsnr` before posting. Sesam parity would require Dunsnr,
-- but that silently drops D365-sourced fields (Sperret, D365Kommentar, Orgnummer) for any
-- vendor Bisnode hasn't DUNS-matched yet — those vendors then NEVER get corrected in
-- SuperOffice (confirmed case: d365_leverandor_id 502782, leverandorsperre cleared in D365
-- but SuperOffice stayed "sperret" forever since the whole row was filtered out). ContactId
-- is already guaranteed non-null upstream (mrt_global_leverandorvurdering's base SO CTE
-- filters contactId IS NOT NULL AND > 0), so no WHERE is needed here — Bisnode-only fields
-- (Dunsnr, Kredittrating, Betalingsanmerkning, Soliditet, Aarsregnskap, Okonomiskforhold,
-- MvaRegistrert, Revisor, RevisorKommentar, Sanksjonert) simply post as null when Bisnode
-- hasn't matched the vendor, which is correct — there's no Bisnode data to show either way.
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_LEVERANDORVURDERING", "leverandorvurdering-superoffice-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'contactId'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
