{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'PersonKonvolutt',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'PersonEpost,KonvoluttId,Type'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for verified envelope person data to Forvalter.
  Mirrors Sesam personkonvolutt-forvalter-endpoint.

  Source: mrt_verified_personkonvolutt (owners[] + recipients[] from stg_verified_envelope).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_MYSQL_DB       Forvalter database name

  MySQL PersonKonvolutt columns (from SHOW COLUMNS):
    KonvoluttId, PersonEpost, Type, Etternavn, Fornavn
  Primary key: [KonvoluttId, PersonEpost, Type]

  Type mapping (Sesam convention):
    owner     → eier
    recipient → mottaker
*/

SELECT
    {{ test_id("email || ':' || envelopeId::VARCHAR || ':' || (CASE type WHEN 'owner' THEN 'eier' ELSE 'mottaker' END)") }}
    email                                                       AS "PersonEpost",
    envelopeId                                                  AS "KonvoluttId",
    CASE type
        WHEN 'owner'     THEN 'eier'
        WHEN 'recipient' THEN 'mottaker'
        ELSE type
    END                                                         AS "Type",
    givenName                                                   AS "Fornavn",
    familyName                                                  AS "Etternavn"
FROM {{ ref('mrt_verified_personkonvolutt') }}
WHERE email IS NOT NULL
  AND envelopeId IS NOT NULL
