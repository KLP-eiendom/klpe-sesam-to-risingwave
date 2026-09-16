{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
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
  MySQL sink for user data to Kundeportal.
  Mirrors Sesam user-kundeportal-endpoint.

  Source: mrt_global_user (Sesam global-user merge: canonical user webhook + csuser).

  Sesam row logic (user-kundeportal pipe):
    - email valid (`*@*.*`) and not containing `/`
    - dedup by email: prefer active user, then lowest personId
    - IsDeleted = 1 only if ALL user instances for this email are retired or deleted

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_DB             Kundeportal database name

  Sesam fields: SuperOfficeId, Registered, BrukerId, Epost, Mobilnr,
                Fornavn, Etternavn, IsDeleted, HasKundeportalInteresse, Updated

  Gap vs Sesam:
    Mobilnr   — Sesam sources from D365 ansatt:phone (not available in stg_d365_ansatt);
                using SO mobilePhone (csuser phone fallback via the mart).
*/

WITH dedup AS (
    SELECT
        *,
        -- 1 kun hvis ALLE instanser for denne e-posten er retired/deleted:
        MIN(CASE WHEN retired OR _deleted THEN 1 ELSE 0 END) OVER (PARTITION BY bruker_id) AS all_instances_deleted,
        ROW_NUMBER() OVER (
            PARTITION BY bruker_id
            ORDER BY
                CASE WHEN retired OR _deleted THEN 1 ELSE 0 END ASC,
                personId ASC
        ) AS email_rank
    FROM {{ ref('mrt_global_user') }}
    WHERE bruker_id LIKE '%@%.%'
      AND bruker_id NOT LIKE '%/%'
)

SELECT
        {{ test_id("personId") }}
personId            AS "SuperOfficeId",
    registered          AS "Registered",
    registered          AS "Created",
    bruker_id           AS "BrukerId",
    bruker_id           AS "Epost",
    mobilePhone         AS "Mobilnr",
    REGEXP_REPLACE(firstName, '[\x{10000}-\x{10FFFF}]', '', 'g') AS "Fornavn",
    REGEXP_REPLACE(lastName, '[\x{10000}-\x{10FFFF}]', '', 'g')  AS "Etternavn",
    all_instances_deleted AS "IsDeleted",
    -- personInterestIds is a semicolon-separated string e.g. 'NO:"Kundeportal";NO:"Kontraktsansvarlig";'.
    -- Sesam also checks the person's individual superoffice-personinterest rows separately —
    -- a user can carry a Kundeportal interest there without it appearing in the webhook summary.
    CASE WHEN LOWER(personInterestIds::TEXT) LIKE '%kundeportal%'
           OR personinterestNames LIKE '%kundeportal%'
         THEN 1 ELSE 0 END
                        AS "HasKundeportalInteresse",
    updated             AS "Updated",
    updated             AS "LastUpdated"
FROM dedup
WHERE email_rank = 1
