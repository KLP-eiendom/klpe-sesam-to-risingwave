{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Bruker',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'BrukerId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  Internal user data to Forvalter (MySQL sink).
  Now sources directly from mrt_global_internaluser which contains centralized filtering.
*/

SELECT
        {{ test_id("email") }}
COALESCE(personId, 0)                AS "SuperOfficeId",
    COALESCE(so_registeredDate, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    email                                AS "BrukerId",
    roleName                             AS "SoRole",
    email                                AS "Epost",
    copyEmail                            AS "KopiEpost",
    so_firstName                         AS "Fornavn",
    so_lastName                          AS "Etternavn",
    0                                    AS "IsDeleted",
    region                               AS "PortfolioRegion",
    so_updatedDate                       AS "LastUpdated",
    fult_navn                            AS "FulltNavn",
    bruker_id                            AS "D365Initialer"
FROM {{ ref('mrt_global_internaluser') }}
