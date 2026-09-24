{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Faktura',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for invoice data to Kundeportal.
  Mirrors Sesam faktura-kundeportal-endpoint.

  Source: mrt_global_invoice (stg_d365_faktura_detaljer).

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_MYSQL_DB       Kundeportal database name
*/

SELECT
        {{ test_id("_id") }}
    _id                                                             AS "Id",
    kunde_nummer                                                    AS "KundeNummer",
    faktura_nummer                                                  AS "FakturaNummer",
    kid                                                             AS "Kid",
    forfallsdato                                                    AS "ForfallsDato",
    fakturadato                                                     AS "FakturaDato",
    betalt_dato                                                     AS "BetaltDato",
    sum                                                             AS "Sum",
    CASE WHEN fil_finnes IS NULL OR fil_finnes = TRUE THEN pdf_filnavn ELSE '' END AS "PdfFileName",
    siste_innbetaling                                               AS "SisteInnbetaling",
    COALESCE(ABS(sum_innbetalt), 0)                                 AS "SumInnbetalt",
    sum_utestaaende                                                 AS "SumUtestaaende",
    sum_utestaaende_forsinket                                       AS "SumUtestaaendeForsinket",
    sum_utestaaende_forsinket_dager                                 AS "SumUtestaaendeForsinketDager",
    kontraktsnummer                                                 AS "KontraktsNummer",
    bygg_nummer                                                     AS "ByggNummer",
    "Created",
    "LastUpdated"
FROM {{ ref('mrt_global_invoice') }}
WHERE _id IS NOT NULL
  -- Mirror Sesam faktura-kundeportal: only electronically-sent invoices dated after 2008-01-01.
  -- (Sesam also keeps axapta:Invoice rows; RW is d365-only, so that branch is N/A here.)
  AND fakturadato > '2008-01-01'
  AND faktura_sendt_elektronisk = 1
