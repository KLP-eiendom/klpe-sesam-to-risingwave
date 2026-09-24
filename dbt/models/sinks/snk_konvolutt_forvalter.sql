{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Konvolutt',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

WITH source AS (
    SELECT
        id,
        greeting,
        completed,
        expired,
        expiration,
        created,
        publishDate,
        sender_email
    FROM {{ ref('mrt_verified_envelope') }}
    WHERE id IS NOT NULL
)
SELECT
    id              AS "Id",
    greeting        AS "Navn",
    completed       AS "Fullfoert",
    expired         AS "Utloept",
    expiration      AS "FristDato",
    COALESCE(created::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "OpprettetDato",
    COALESCE(created::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    publishDate     AS "PublisertDato",
    sender_email    AS "AvsenderEpost"
FROM source
