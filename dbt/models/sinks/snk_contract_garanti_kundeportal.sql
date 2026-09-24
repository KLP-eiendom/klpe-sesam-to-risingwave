{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'KontraktGaranti',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'GarantiId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for contract garanti data to Kundeportal.
  Mirrors Sesam contract-garanti-kundeportal-endpoint.

  Source: stg_d365_garanti.
*/

SELECT
    {{ test_id("garanti_id::VARCHAR") }}
    garanti_id::VARCHAR                                     AS "GarantiId",
    garanti_nummer::VARCHAR                                  AS "GarantiNummer",
    (kontrakt_id::VARCHAR || '.' || UPPER(firma_id))         AS "KontraktId",
    klassifiseringstype                                     AS "Klassifiseringstype",
    bygg_avdeling_id                                        AS "ByggNummer",
    garantibelop                                            AS "Amount",
    '1970-01-01 00:00:00'::TIMESTAMP                        AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                        AS "LastUpdated"
FROM {{ ref('stg_d365_garanti') }}
WHERE garanti_id IS NOT NULL
