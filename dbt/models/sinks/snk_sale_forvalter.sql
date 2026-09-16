{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Salg',
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
  MySQL sink for sale data to Forvalter.
  Mirrors Sesam sale-forvalter-endpoint.

  Source: mrt_global_sale (FULL OUTER JOIN of SO sale poller + webhook).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, Created, OpprettetAv, LastUpdated, EndretAv, SoContactId,
                Kundenummer, Beskrivelse, Belop, Type, Status, SolgtDato, ProsjektId, ProsjektNavn

*/

SELECT
        {{ test_id("saleId") }}
    saleId                                  AS "Id",
    registeredDate                          AS "Created",
    registeredBy                            AS "OpprettetAv",
    updatedDate                             AS "LastUpdated",
    updatedBy                               AS "EndretAv",
    contactId                               AS "SoContactId",
    kundenummer                             AS "Kundenummer",
    description                             AS "Beskrivelse",
    amount                                  AS "Belop",
    saleType                                AS "Type",
    saleStatus                              AS "Status",
    date                                    AS "SolgtDato",
    projectId                               AS "ProsjektId",
    projectName                             AS "ProsjektNavn"
FROM {{ ref('mrt_sale_forvalter') }}
WHERE saleId IS NOT NULL
