{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'PersonInterest',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'BrukerId,PersIntId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for person interest data to Kundeportal.
  Mirrors Sesam personinterest-kundeportal-endpoint.

  Source: mrt_superoffice_personinterest.
*/

SELECT
    {{ test_id("\"BrukerId\" || ':' || \"PersIntId\"") }}
    "BrukerId",
    "PersIntId",
    "Name",
    "SuperOfficeId",
    "Registered",
    COALESCE("Registered", '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    "Updated",
    COALESCE("Updated", '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated"
FROM {{ ref('mrt_superoffice_personinterest') }}
