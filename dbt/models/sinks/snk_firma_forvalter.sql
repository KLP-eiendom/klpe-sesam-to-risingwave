{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Firma',
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
  MySQL sink for company data to Forvalter.
  Mirrors Sesam firma-forvalter-endpoint.

  Source: mrt_global_firma (stg_d365_firma).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, Navn, Region, OrgNivaa2, OrgNivaa3

*/

SELECT
        {{ test_id("firma_id") }}
firma_id                                    AS "Id",
    navn                                        AS "Navn",
    region                                      AS "Region",
    orglevel2                                   AS "OrgNivaa2",
    orglevel3                                   AS "OrgNivaa3",
    '1970-01-01 00:00:00'::TIMESTAMP            AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP            AS "LastUpdated"
FROM {{ ref('stg_d365_firma') }}
WHERE firma_id IS NOT NULL