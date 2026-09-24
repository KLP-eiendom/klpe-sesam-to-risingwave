{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'BrukerKunde',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'SoContactId,BrukerId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Mirrors Sesam usercustomer-kundeportal: one row per (SoContactId, BrukerId) — PK of the
  MySQL BrukerKunde table. Sesam filters: SoContactId not null/''/0, BrukerId nonempty,
  email valid (`*@*.*`) and not containing `/`. No retired filter (unlike usercustomer-bq).
  Dedup keeps the lowest personId per (contact, email) pair to match the upsert PK.
  NB: when a (contact, email) has duplicate person records, Sesam's endpoint picks a
  personId non-deterministically (ingestion-order last-write-wins — neither min nor max),
  so strict SuperOfficeId parity on those ~0.6% dup pairs is not achievable; NEGLECT.
*/

WITH dedup AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY contactid, bruker_id ORDER BY personid ASC) AS pair_rank
    FROM {{ ref('mrt_global_user') }}
    WHERE personid IS NOT NULL
      AND contactid IS NOT NULL
      AND contactid <> 0
      AND bruker_id LIKE '%@%.%'
      AND bruker_id NOT LIKE '%/%'
      AND NOT _deleted
)

SELECT
        {{ test_id("(contactid)::VARCHAR || ':' || (bruker_id)::VARCHAR") }}
    personid  AS "SuperOfficeId",
    '2024-01-01 00:00:00'::TIMESTAMP AS "Created",
    '2024-01-01 00:00:00'::TIMESTAMP AS "LastUpdated",
    contactid AS "SoContactId",
    bruker_id AS "BrukerId"
FROM dedup
WHERE pair_rank = 1
