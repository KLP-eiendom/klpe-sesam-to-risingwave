{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'KostKategori',
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
  MySQL sink for cost category data to Forvalter.
  Mirrors Sesam kostkategori-forvalter-endpoint.

  Source: mrt_global_kostkategori (stg_d365_kostkategori).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, Navn, Beskrivelse, GruppeId, GruppeNavn, GruppeBeskrivelse

*/

SELECT
        {{ test_id("kategori_id") }}
kategori_id                                                          AS "Id",
    kategori_navn                                                        AS "Navn",
    kategori                                                             AS "Beskrivelse",
    CASE WHEN kategori_id = 'PLED' THEN 'I'
         ELSE kategorigruppe_id
    END                                                                  AS "GruppeId",
    CASE WHEN kategori_id = 'PLED' THEN 'Intern prosjektledelse'
         ELSE kategorigruppe_navn
    END                                                                  AS "GruppeNavn",
    CASE WHEN kategori_id = 'PLED' THEN 'I - Intern prosjektledelse'
         ELSE kategorigruppe
    END                                                                  AS "GruppeBeskrivelse"
FROM {{ ref('stg_d365_kostkategori') }}
WHERE kategori_id ~ '^[0-9]+$'
   OR kategori_id = 'PLED'
