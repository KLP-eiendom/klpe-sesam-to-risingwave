{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Leverandorvurdering',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Orgnummer,SuperOfficeContactId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for vendor assessment data to Forvalter.
  Mirrors Sesam leverandorvurdering-forvalter-endpoint.

  Source: mrt_global_leverandorvurdering.

  MySQL table PK: composite (Orgnummer, SuperOfficeContactId).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name
*/

SELECT
        {{ test_id("unique_orgnr") }}
unique_orgnr                                AS "Orgnummer",
    contactId                                   AS "SuperOfficeContactId",
    d365_leverandor_id                          AS "LeverandorId",
    navn                                        AS "Navn",
    klassifiseringkode                          AS "KlassifiseringKode",
    klassifiseringbeskrivelse                   AS "KlassifiseringBeskrivelse",
    registeredDate::TIMESTAMP                   AS "Created",
    updatedDate::TIMESTAMP                      AS "LastUpdated"
FROM {{ ref('mrt_global_leverandorvurdering') }}
WHERE contactId IS NOT NULL
