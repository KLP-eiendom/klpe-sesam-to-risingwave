{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Person',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Mirrors Sesam user-person-forvalter, which sources from global-user (MERGE of
  superoffice-migrateduser webhook + superoffice-csuser poll) — not csuser alone.
  Previously this sink read stg_superoffice_csuser directly, missing every person
  who only exists on the superoffice-user webhook side.

  Id mirrors the superoffice-entity-poller csuser IdExpression
  (concat(personId, "-", lower(email))) and Sesam's own global-user _uniqueId, so
  existing csuser-driven "Person" rows keep the same key — this only adds rows,
  it doesn't reassign any existing primary key.

  Filters mirror the Sesam DTL: SoContactId must be present and > 0 (Sesam treats
  contactId=0 as "no contact" via filter(gt(_,0), ...) before its coalesce — a plain
  IS NOT NULL would wrongly admit the ~3.9k rows where contactId is literally 0),
  and Epost must be a plausibly-formed email (contains "@" then "." after it, no "/").
*/
WITH filtered AS (
    SELECT
        CONCAT(personId, '-', LOWER(email))    AS _id,
        personId,
        NULLIF(contactId, 0)                   AS contactId,
        LOWER(email)                           AS email,
        fullName,
        firstName,
        lastName,
        registered
    FROM {{ ref('mrt_global_user') }}
    WHERE personId IS NOT NULL
      AND email IS NOT NULL AND email != ''
      AND email LIKE '%@%.%'
      AND email NOT LIKE '%/%'
),

-- See mrt_sale_forvalter.sql for the confirmed case (kundenummer 600335: contactId 8636
-- is the real company, 18327 is its Bergen department, both carry the same D365
-- kundenummer). Only null out Kundenummer for a department contact when a non-department
-- sibling ALSO carries the same kundenummer (a proven duplicate) — a contact that merely
-- has a department filled in, with no such sibling, is a normal single contact.
customer_has_primary AS (
    SELECT kundenummer, BOOL_OR(COALESCE(department, '') = '') AS has_primary_contact
    FROM {{ ref('mrt_global_customer') }}
    WHERE kundenummer IS NOT NULL AND kundenummer != ''
    GROUP BY kundenummer
)

SELECT
        {{ test_id("_id") }}
    _id                                                                       AS "Id",
    f.personId::BIGINT                                                        AS "SoPersonId",
    f.contactId::BIGINT                                                       AS "SoContactId",
    f.email                                                                   AS "Epost",
    COALESCE(NULLIF(f.fullName, ''), NULLIF(TRIM(COALESCE(f.firstName, '') || ' ' || COALESCE(f.lastName, '')), ''), f.email, f._id) AS "Navn",
    -- Sesam looks Kundenummer up via a hop into global-customer by contactId (gc.number),
    -- NOT csuser's own contactNumber field — a person can be linked to a customer whose
    -- number was never captured on the csuser side.
    CASE
        WHEN COALESCE(c.department, '') != '' AND COALESCE(chp.has_primary_contact, FALSE)
        THEN NULL
        ELSE NULLIF(c.kundenummer, '')
    END                                                                       AS "Kundenummer",
    COALESCE(f.registered::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP)                              AS "Created"
FROM filtered f
LEFT JOIN {{ ref('mrt_global_customer') }} c
    ON c.contactid = f.contactId
LEFT JOIN customer_has_primary chp
    ON chp.kundenummer = c.kundenummer
WHERE f.contactId IS NOT NULL
