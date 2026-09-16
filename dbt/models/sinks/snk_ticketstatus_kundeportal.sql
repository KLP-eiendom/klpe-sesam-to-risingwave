{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Sakstatus',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'SakstatusId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for ticket status data to Kundeportal.
  Mirrors Sesam ticketstatus-kundeportal-endpoint.

  Source: mrt_global_ticketstatus (stg_superoffice_ticketstatus).

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_DB             Kundeportal database name

  Sesam fields: SakstatusId, Kode, Navn, System
  Mapping (mirrors Sesam ticketstatus-kundeportal DTL):
    Kode   = status   (English status code, e.g. 'Active'/'Closed') — NOT _id
    Navn   = name      (localized display name, e.g. 'Aktiv')
    System = 'superoffice' (constant; Sesam emits it when ticketStatusId is set)
*/

SELECT
        {{ test_id("ticketStatusId") }}
ticketStatusId                              AS "SakstatusId",
    status                                      AS "Kode",
    name                                        AS "Navn",
    'superoffice'                               AS "System",
    '1970-01-01 00:00:00'::TIMESTAMP            AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP            AS "LastUpdated"
FROM {{ ref('stg_superoffice_ticketstatus') }}
WHERE ticketStatusId IS NOT NULL
