{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  BigQuery sink for service contract data.
  Mirrors Sesam serviceavtale-bq → serviceavtale-bq-rest-endpoint → bigquery-api.

  Source: stg_fdvweb_serviceavtale (FDVWeb GetServiceAvtale poller).

  Sesam fields: uniqueId, BuildingId, Id, Nummer, Navn, Firma, Pris, PrisFrekvens,
                Oppsigelsesfrist, Varighet, Startdato, Utlopsdato, Fornyelse,
                Prisregulering, Omfang, Annet, Type, Bygningsdel, Ansvarlig,
                Oppfolgingsdato, Garantidato
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("CONCAT(byggid, '_', id)") }}
CONCAT(byggid, '_', id)    AS "uniqueId",
    byggid                     AS "BuildingId",
    id::DECIMAL                AS "Id",
    nummer                     AS "Nummer",
    navn                       AS "Navn",
    firma                      AS "Firma",
    REPLACE(pris, ',', '.')::DECIMAL AS "Pris",
    prisfrekvens               AS "PrisFrekvens",
    oppsigelsesfrist           AS "Oppsigelsesfrist",
    varighet                   AS "Varighet",
    startdato AT TIME ZONE 'UTC'       AS "Startdato",
    utlopsdato AT TIME ZONE 'UTC'      AS "Utlopsdato",
    fornyelse                          AS "Fornyelse",
    prisregulering                     AS "Prisregulering",
    omfang                             AS "Omfang",
    annet                              AS "Annet",
    type                               AS "Type",
    bygningsdel                        AS "Bygningsdel",
    ansvarlig                          AS "Ansvarlig",
    oppfolgingsdato AT TIME ZONE 'UTC' AS "Oppfolgingsdato",
    garantidato AT TIME ZONE 'UTC'     AS "Garantidato"
FROM {{ ref('stg_fdvweb_serviceavtale') }}
WHERE byggid IS NOT NULL
  AND id IS NOT NULL
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'bigquery',
    type = 'upsert',
    force_compaction = 'true',
    primary_key = 'uniqueId',
    bigquery.project = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    bigquery.dataset = 'KDI',
    bigquery.table = 'FdvwebServiceavtale',
    bigquery.credentials = SECRET risingwave_gcp_sa
);
{% endif %}
