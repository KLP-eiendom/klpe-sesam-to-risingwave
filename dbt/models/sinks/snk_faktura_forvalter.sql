{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
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
  MySQL sink for invoice data to Forvalter.
  Mirrors Sesam faktura-forvalter-endpoint.

  Source: mrt_global_invoice (stg_d365_faktura_detaljer).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name
*/

SELECT
        {{ test_id("_id") }}
    _id                                                             AS "Id",
    kunde_nummer                                                    AS "KundeNummer",
    faktura_nummer                                                  AS "FakturaNummer",
    forfallsdato                                                    AS "ForfallsDato",
    fakturadato                                                     AS "FakturaDato",
    betalt_dato                                                     AS "BetaltDato",
    sum                                                             AS "Sum",
    siste_innbetaling                                               AS "SisteInnbetaling",
    COALESCE(ABS(sum_innbetalt), 0)                                 AS "SumInnbetalt",
    sum_utestaaende                                                 AS "SumUtestaaende",
    sum_utestaaende_forsinket                                       AS "SumUtestaaendeForsinket",
    ROUND(sum_utestaaende_forsinket::NUMERIC)::DOUBLE PRECISION     AS "SumUtestaaendeForsinketAvrundet",
    sum_utestaaende_forsinket_dager                                 AS "SumUtestaaendeForsinketDager",
    kontraktsnummer                                                 AS "KontraktsNummer",
    "Created",
    "LastUpdated"
FROM {{ ref('mrt_global_invoice') }}
WHERE _id IS NOT NULL
  -- Mirror Sesam faktura-forvalter: only electronically-sent invoices dated after 2008-01-01.
  -- (Sesam also keeps axapta:Invoice rows; RW is d365-only, so that branch is N/A here.)
  AND fakturadato > '2008-01-01'
  AND faktura_sendt_elektronisk = 1
