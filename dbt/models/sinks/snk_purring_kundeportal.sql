{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Purring',
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
  MySQL sink for dunning/reminder data to Kundeportal.
  Mirrors Sesam purring-kundeportal-endpoint.

  Source: mrt_global_purring (stg_d365_purring_detaljer).

  MySQL Purring columns: Id, KundeNummer, FakturaNummer, ForfallsDato, Kid,
    FakturaDato, BetaltDato, PdfFileName, Status (int), Type (int).
  stg_d365_purring_detaljer: id, kundenummer, faktura_id, forfall_dato, belop,
    valuta, purring_dato, purring_nivaa, beskrivelse, status (varchar).

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_DB             Kundeportal database name
*/

SELECT
        {{ test_id("id") }}
id                                                            AS "Id",
    kunde_nummer                                                  AS "KundeNummer",
    purring_nummer                                                AS "FakturaNummer",
    kid                                                           AS "Kid",
    COALESCE(forfallsdato, '1970-01-01 00:00:00'::TIMESTAMP)     AS "ForfallsDato",
    COALESCE(faktura_dato, '1970-01-01 00:00:00'::TIMESTAMP)     AS "FakturaDato",
    CASE WHEN fil_finnes IS NULL OR fil_finnes = TRUE THEN pdf_filnavn ELSE '' END AS "PdfFileName",
    COALESCE(CAST(status AS INT), 0)                              AS "Status",
    COALESCE(CAST(purring_kode AS INT), 0)                        AS "Type",
    "Created",
    "LastUpdated"
FROM {{ ref('mrt_global_purring') }}
WHERE purring_nummer IS NOT NULL
