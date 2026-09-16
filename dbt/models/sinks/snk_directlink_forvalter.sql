{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'DirekteLenke',
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
  MySQL sink for Leko direct-link data to Forvalter.
  Mirrors Sesam directlink-forvalter-endpoint.

  Source: mrt_lekoworker_directlink (LekoWorker webhook).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id (soDokumentId:superoffice-document), DokumentId, KonvoluttId,
                KundeLenke, KundeNummer, LekoId, SoDokumentId,
                KontraktLenke, KontraktNummer


*/

SELECT
        {{ test_id("CONCAT(payload->>'soDokumentId', ':superoffice-document')") }}
    CONCAT(payload->>'soDokumentId', ':superoffice-document') AS "Id",
    payload->>'dokumentId'                  AS "DokumentId",
    payload->>'konvoluttId'                 AS "KonvoluttId",
    payload->>'kundeLenke'                  AS "KundeLenke",
    payload->>'kundeNummer'                 AS "KundeNummer",
    payload->>'lekoId'                      AS "LekoId",
    CASE
        WHEN payload->>'soDokumentId' ~ '^[0-9]+$' THEN (payload->>'soDokumentId')::BIGINT
        ELSE NULL
    END                                     AS "SoDokumentId",
    payload->>'kontraktLenke'               AS "KontraktLenke",
    payload->>'kontraktNummer'              AS "KontraktNummer",
    '1970-01-01 00:00:00'::TIMESTAMP        AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP        AS "LastUpdated"
FROM {{ ref('stg_lekoworker_directlink') }}
WHERE payload->>'soDokumentId' ~ '^[0-9]+$'
  AND (payload->>'soDokumentId')::BIGINT > 0
