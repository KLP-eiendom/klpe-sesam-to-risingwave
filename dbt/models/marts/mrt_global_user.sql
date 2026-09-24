{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-user.
  MERGE of superoffice-user (canonical user webhook, priority) and superoffice-csuser (REST poll)
  on personId — Sesam: datasets [superoffice-migrateduser, superoffice-csuser], equality on
  personId, identity=first (user side wins shared fields).

  NOTE on the user side: stg_superoffice_user must hold the CANONICAL user set (Sesam
  superoffice-migrateduser, ~6701), not the raw ~36k person feed — see seed_findings.md F1.
  Seeded via seed_from_sesam.py (sesam_dataset override). When live webhook streaming resumes,
  the reduction must be reproduced here from a business field (associateDbId candidate).

  Column semantics for downstream sinks:
    contactId     — COALESCE(user, csuser): Sesam usercustomer-kundeportal SoContactId semantics
    su_contactId  — user-webhook side ONLY: Sesam usercustomer-bq kunde_id semantics
    contactNumber — from csuser (closes the documented contactNumber gap)
    _source       — observability: which side produced the row
*/

WITH personinterest_agg AS (
    -- Sesam's user-kundeportal HasKundeportalInteresse also checks the person's individual
    -- superoffice-personinterest rows (via a hop), not just personInterestIds — a user can have
    -- a "Kundeportal" personinterest entry without it showing up in the webhook's summary string.
    SELECT
        personid,
        STRING_AGG(LOWER(REPLACE(REPLACE(name, '";', ''), 'NO:"', '')), ';') AS interest_names
    FROM {{ ref('stg_superoffice_personinterest') }}
    GROUP BY personid
),

latest_user AS (
    SELECT
        payload,
        (payload->>'personId')::BIGINT AS person_id
    FROM {{ ref('stg_superoffice_user') }}
    WHERE (payload->>'personId')::BIGINT IS NOT NULL
      AND (payload->>'personId')::BIGINT > 0
),

latest_csuser AS (
    SELECT
        personid::BIGINT    AS person_id,
        NULLIF(contactid, '')::BIGINT AS contactid,
        contactnumber,
        email,
        firstname,
        lastname,
        phone,
        registered,
        updated,
        ROW_NUMBER() OVER (
            PARTITION BY personid::BIGINT
            ORDER BY _id
        ) AS rn
    FROM {{ ref('stg_superoffice_csuser') }}
    -- guard-before-cast (F2 class): a single non-numeric value would fail the whole MV
    WHERE personid ~ '^[0-9]+$'
)

SELECT
    COALESCE(u.person_id, cu.person_id)                              AS personId,
    -- 0 is SuperOffice's "no contact linked" sentinel, not a real contactId — NULLIF it on
    -- EACH side before coalescing, else a user-side 0 masks a valid csuser-side contactId.
    COALESCE(NULLIF((u.payload->>'contactId')::BIGINT, 0), NULLIF(cu.contactid, 0)) AS contactId,
    (u.payload->>'contactId')::BIGINT                                AS su_contactId,
    COALESCE(u.payload->>'email', cu.email)                          AS email,
    LOWER(COALESCE(u.payload->>'email', cu.email))                   AS bruker_id,
    COALESCE(u.payload->>'firstName', cu.firstname)                  AS firstName,
    COALESCE(u.payload->>'lastName', cu.lastname)                    AS lastName,
    u.payload->>'fullName'                                           AS fullName,
    COALESCE(u.payload->>'mobilePhone', cu.phone)                    AS mobilePhone,
    u.payload->>'roleName'                                           AS roleName,
    u.payload->>'region'                                             AS region,
    u.payload->>'copyEmail'                                          AS copyEmail,
    COALESCE((u.payload->>'retired')::BOOLEAN, FALSE)                AS retired,
    u.payload->'personInterestIds'                                   AS personInterestIds,
    pi.interest_names                                                AS personinterestNames,
    NULLIF(u.payload->>'personRegisteredDate', '')::TIMESTAMPTZ      AS personRegisteredDate,
    NULLIF(u.payload->>'personUpdatedDate', '')::TIMESTAMPTZ         AS personUpdatedDate,
    COALESCE(
        NULLIF(REGEXP_REPLACE(u.payload->>'registered', '^~t', ''), '')::TIMESTAMPTZ,
        NULLIF(cu.registered, '')::TIMESTAMPTZ,
        '1970-01-01 00:00:00'::TIMESTAMPTZ
    ) AS registered,
    COALESCE(
        NULLIF(REGEXP_REPLACE(u.payload->>'updated', '^~t', ''), '')::TIMESTAMPTZ,
        NULLIF(cu.updated, '')::TIMESTAMPTZ,
        '1970-01-01 00:00:00'::TIMESTAMPTZ
    ) AS updated,
    cu.contactnumber                                                 AS contactNumber,
    CASE WHEN u.person_id IS NOT NULL THEN 'user' ELSE 'csuser' END  AS _source,
    COALESCE((u.payload->>'_deleted')::BOOLEAN, FALSE)               AS _deleted
FROM latest_user u
FULL OUTER JOIN (SELECT * FROM latest_csuser WHERE rn = 1) cu
    ON cu.person_id = u.person_id
LEFT JOIN personinterest_agg pi
    ON pi.personid = COALESCE(u.person_id, cu.person_id)
