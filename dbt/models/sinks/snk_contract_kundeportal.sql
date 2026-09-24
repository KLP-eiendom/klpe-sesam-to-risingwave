{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Kontrakt',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'KontraktId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

SELECT
        {{ test_id("_id") }}
    _id                                                 AS "KontraktId",
    kontrakt_id                                        AS "Kontraktsnummer",
    kundenummer                                        AS "Kundenummer",
    kontrakt_navn                                      AS "Navn",
    byggnummer                                         AS "Bygningsnummer",
    gyldig_fra                                         AS "GyldigFra",
    gyldig_til                                         AS "GyldigTil",
    fra_dato                                           AS "KontraktFra",
    opphoersdato                                       AS "KontraktTil",
    kontrakt_dato                                      AS "Kontraktsdato",
    COALESCE(leie, 0)                                   AS "ArligLeie",
    COALESCE(felleskost, 0)                              AS "ArligFellesKostnad",
    COALESCE(eiendomsskatt, 0)                           AS "ArligEiendomsskatt",
    status_kode                                        AS "StatusKode",
    status_navn                                        AS "StatusTekst",
    lokal_valuta                                       AS "LokalValuta",
    kontrakt_id || ' ' || COALESCE(kontrakt_navn, '')  AS "Visningsnavn",
    '1970-01-01 00:00:00'::TIMESTAMP                   AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                   AS "LastUpdated"
FROM {{ ref('stg_d365_kontrakt') }}
WHERE _id IS NOT NULL
  AND kundenummer IS NOT NULL
