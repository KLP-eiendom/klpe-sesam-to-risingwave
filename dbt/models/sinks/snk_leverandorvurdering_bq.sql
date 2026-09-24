{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  BigQuery sink for vendor assessment data.
  Mirrors Sesam leverandorvurdering-bigquery-endpoint.

  Source: mrt_global_leverandorvurdering.

  BQ table: KDI.SuperOfficeLeverandorVurdering_sesam (44 columns).
  REPEATED fields are written as single-element ARRAYs; NULLABLE as scalars.
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("ARRAY[contactId]") }}
-- Sesam system fields
    array_remove(ARRAY[contactId::VARCHAR], NULL)            AS "_ids",

    -- Vendor assessment fields (REPEATED → single-element ARRAY)
    array_remove(ARRAY[adm], NULL)                           AS "leverandorvurdering_bq__adm",
    array_remove(ARRAY[aarsregnskap], NULL)                  AS "leverandorvurdering_bq__aarsregnskap",
    array_remove(ARRAY[betalingsanmerkning], NULL)           AS "leverandorvurdering_bq__betalingsanmerkning",
    array_remove(ARRAY[bransje], NULL)                       AS "leverandorvurdering_bq__bransje",
    array_remove(ARRAY[bransje_so], NULL)                    AS "leverandorvurdering_bq__bransje_so",
    array_remove(ARRAY[contactId], NULL)                     AS "leverandorvurdering_bq__contactid",
    d365kommentar                                            AS "leverandorvurdering_bq__d365kommentar",
    array_remove(ARRAY[dv], NULL)                            AS "leverandorvurdering_bq__dv",
    array_remove(ARRAY[driftsforhold_sistvurdert::TIMESTAMPTZ], NULL) AS "leverandorvurdering_bq__driftsforhold_sistvurdert",
    dunsnr::VARCHAR                                          AS "leverandorvurdering_bq__dunsnr",
    array_remove(ARRAY[eu], NULL)                            AS "leverandorvurdering_bq__eu",
    array_remove(ARRAY[evalueringskommentar], NULL)          AS "leverandorvurdering_bq__evalueringskommentar",
    array_remove(ARRAY[fo], NULL)                            AS "leverandorvurdering_bq__fo",
    industrikode                                             AS "leverandorvurdering_bq__industrikode",
    industrikode_beskrivelse                                 AS "leverandorvurdering_bq__industrikode_beskrivelse",
    array_remove(ARRAY[innmeldtav], NULL)                    AS "leverandorvurdering_bq__innmeldtav",
    array_remove(ARRAY[klassifiseringbeskrivelse], NULL)     AS "leverandorvurdering_bq__klassifiseringbeskrivelse",
    array_remove(ARRAY[klassifiseringkode], NULL)            AS "leverandorvurdering_bq__klassifiseringkode",
    array_remove(ARRAY[kredittrating], NULL)                 AS "leverandorvurdering_bq__kredittrating",
    d365_leverandor_id                                       AS "leverandorvurdering_bq__leverandorid",
    array_remove(ARRAY[lokasjon], NULL)                      AS "leverandorvurdering_bq__lokasjon",
    manuellsanksjonsjekkbeskrivelse                          AS "leverandorvurdering_bq__manuellsanksjonsjekkbeskrivelse",
    manuellsanksjonsjekkkode                                 AS "leverandorvurdering_bq__manuellsanksjonsjekkkode",
    manuellsanksjonsjekkkommentar                            AS "leverandorvurdering_bq__manuellsanksjonsjekkkommentar",
    array_remove(ARRAY[miljodokumentasjon], NULL)            AS "leverandorvurdering_bq__miljodokumentasjon",
    mvaregistrert                                            AS "leverandorvurdering_bq__mvaregistrert",
    array_remove(ARRAY[navn], NULL)                          AS "leverandorvurdering_bq__navn",
    array_remove(ARRAY[okonomiskforhold_sistvurdert::TIMESTAMPTZ], NULL) AS "leverandorvurdering_bq__okonomiskforhold_sistvurdert",
    array_remove(ARRAY[orgnr], NULL)                         AS "leverandorvurdering_bq__orgnummer",
    array_remove(ARRAY[rammeavtale], NULL)                   AS "leverandorvurdering_bq__rammeavtale",
    revisor                                                  AS "leverandorvurdering_bq__revisor",
    revisorkommentar                                         AS "leverandorvurdering_bq__revisorkommentar",
    array_remove(ARRAY[sf], NULL)                            AS "leverandorvurdering_bq__sf",
    array_remove(ARRAY[samfunnsansvar], NULL)                AS "leverandorvurdering_bq__samfunnsansvar",
    sanksjonert                                              AS "leverandorvurdering_bq__sanksjonert",
    array_remove(ARRAY[soliditet::VARCHAR], NULL)            AS "leverandorvurdering_bq__soliditet",
    sperret                                                  AS "leverandorvurdering_bq__sperret",
    underavvikling                                           AS "leverandorvurdering_bq__underavvikling",
    array_remove(ARRAY[unntak], NULL)                        AS "leverandorvurdering_bq__unntak",
    konsernintern                                            AS "leverandorvurdering_bq__konsernintern",
    contactId::VARCHAR                                       AS "_id",
    NULL::BOOLEAN                                            AS "_deleted",
    NULL::INT8                                               AS "_updated"
FROM {{ ref('mrt_global_leverandorvurdering') }}
-- leverandorvurdering-bq.conf.json requires is-not-null LeverandorId (a real D365 vendor
-- number) — unlike leverandorvurdering-forvalter, which also accepts vendors pending a D365
-- number (via the mart's uuid-<contactId> placeholder). Filter here, not in the shared mart.
WHERE d365_leverandor_id IS NOT NULL
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'bigquery',
    type = 'upsert',
    force_compaction = 'true',
    primary_key = '_id',
    bigquery.project = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    bigquery.dataset = 'KDI',
    bigquery.table = 'SuperOfficeLeverandorVurdering_sesam',
    bigquery.credentials = SECRET risingwave_gcp_sa
);
{% endif %}
