{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Salg',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'EksternId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for sale data to Kundeportal.
  Mirrors Sesam sale-kundeportal-endpoint.

  Source: mrt_global_sale (FULL OUTER JOIN of SO sale poller + webhook).

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_DB             Kundeportal database name

  Sesam fields: EksternId, Created, OpprettetAv, LastUpdated, EndretAv,
                SoContactId, Kundenummer, Beskrivelse, Belop, Type, Status,
                SolgtDato, ProsjektId, ProsjektNavn

*/

SELECT
        {{ test_id("externalId") }}
externalId                              AS "EksternId",
    registeredDate                          AS "Created",
    registeredBy                            AS "OpprettetAv",
    updatedDate                             AS "LastUpdated",
    updatedBy                               AS "EndretAv",
    contactId                               AS "SoContactId",
    kundenummer                             AS "Kundenummer",
    description                             AS "Beskrivelse",
    amount                                  AS "Belop",
    -- kundeportal maps the SuperOffice `type` field (Sesam sale-kundeportal endpoint).
    -- NB: sale-forvalter uses saleType instead — do not "align" these two sinks.
    type                                    AS "Type",
    saleStatus                              AS "Status",
    date                                    AS "SolgtDato",
    projectId                               AS "ProsjektId",
    projectName                             AS "ProsjektNavn"
FROM {{ ref('mrt_sale_forvalter') }}
WHERE saleId IS NOT NULL
