{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Prosjekt',
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
  MySQL sink for project data to Forvalter.
  Mirrors Sesam prosjekt-forvalter-endpoint.

  Source: mrt_global_project (FULL OUTER JOIN of SO project poller + webhook).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, Navn, Status, Type, Beskrivelse (= text), OpprettetAv, EndretAv,
                D365Prosjektnummer (= userDefinedFields["8"] from poller)
*/

SELECT
    {{ test_id("projectId::VARCHAR") }}
    projectId::VARCHAR                          AS "Id",
    name                                        AS "Navn",
    COALESCE(NULLIF(SPLIT_PART(status, '"', 2), ''), status) AS "Status",
    COALESCE(NULLIF(SPLIT_PART(type,   '"', 2), ''), type)   AS "Type",
    text                                        AS "Beskrivelse",
    registeredBy                                AS "OpprettetAv",
    updatedBy                                   AS "EndretAv",
    COALESCE(
        (userDefinedFields::JSONB)->>'SuperOffice:8',
        (userDefinedFields::JSONB)->>'superOffice:8'
    )                                            AS "D365Prosjektnummer",
    COALESCE(registeredDate::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    COALESCE(updatedDate::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP)    AS "LastUpdated"
FROM {{ ref('mrt_global_project') }}
WHERE projectId IS NOT NULL
