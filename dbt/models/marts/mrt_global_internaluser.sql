{{ config(
    materialized='view' if target.name in ('localdev', 'ci') else 'materialized_view'
) }}

/*
  Mirrors Sesam global-internaluser.
  Unified internal user dataset merging D365 employees and relevant SuperOffice users.
  
  Filters applied here (as in Sesam):
  - Valid email format (contains @, no forward slash).
  - Included if:
    - User is an employee in D365 (stg_d365_ansatt).
    - OR user has "Forvalterdashboard" interest in SuperOffice.
*/

WITH so_users_raw AS (
    SELECT
        u.personId,
        u.contactId AS so_contactId,
        LOWER(u.email) AS email,
        u.fullName,
        u.firstName,
        u.lastName,
        u.roleName,
        u.region,
        u.copyEmail,
        u.retired,
        COALESCE(u.updated, u.personUpdatedDate) AS so_updatedDate,
        COALESCE(u.registered, u.personRegisteredDate) AS so_registeredDate,
        u.deleted AS so_deleted,
        sc.interests,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(u.email)
            ORDER BY 
                u.retired ASC,
                CASE 
                    WHEN sc.interests::text LIKE '%Forvalterdashboard%' 
                     AND sc.interests::text LIKE '%"selected": true%' 
                    THEN 0 
                    ELSE 1 
                END ASC,
                u.personId DESC
        ) AS rn
    FROM {{ ref('mrt_superoffice_user') }} u
    LEFT JOIN {{ ref('mrt_superoffice_contactsimple') }} sc ON u.contactId = sc.contactId
    WHERE u.email IS NOT NULL AND u.email != ''
),

so_users AS (
    SELECT
        personId,
        so_contactId,
        email,
        fullName,
        firstName,
        lastName,
        roleName,
        region,
        copyEmail,
        retired,
        so_updatedDate,
        so_registeredDate,
        so_deleted,
        interests
    FROM so_users_raw
    WHERE rn = 1
),

employees AS (
    -- Primary source: D365 Employees
    SELECT
        dl._id,
        dl.bruker_id,
        LOWER(dl.epost) AS email,
        dl.fult_navn,
        dl.phone,
        dl.spraak_id,
        
        so.personId,
        so.so_contactId,
        so.fullName AS so_fullName,
        so.firstName AS so_firstName,
        so.lastName AS so_lastName,
        so.roleName,
        so.region,
        so.copyEmail,
        so.retired,
        so.so_updatedDate,
        so.so_registeredDate,
        so.so_deleted,
        so.interests,
        TRUE AS is_employee
    FROM {{ ref('stg_d365_ansatt') }} dl
    LEFT JOIN so_users so ON LOWER(dl.epost) = so.email
    WHERE dl.epost IS NOT NULL
),

extra_so_users AS (
    -- Secondary source: SO users with interest that are NOT employees
    SELECT
        CAST(so.personId AS VARCHAR) AS _id,
        NULL AS bruker_id,
        so.email,
        so.fullName AS fult_navn,
        NULL AS phone,
        NULL AS spraak_id,
        
        so.personId,
        so.so_contactId,
        so.fullName AS so_fullName,
        so.firstName AS so_firstName,
        so.lastName AS so_lastName,
        so.roleName,
        so.region,
        so.copyEmail,
        so.retired,
        so.so_updatedDate,
        so.so_registeredDate,
        so.so_deleted,
        so.interests,
        FALSE AS is_employee
    FROM so_users so
    WHERE so.email NOT IN (SELECT email FROM employees)
      AND EXISTS (
          SELECT 1 
          FROM jsonb_array_elements(
              CASE WHEN jsonb_typeof(so.interests) = 'array' THEN so.interests ELSE '[]'::jsonb END
          ) AS i 
          WHERE i->>'name' LIKE '%Forvalterdashboard%' 
            AND (i->>'selected')::BOOLEAN = true
      )
),

combined AS (
    SELECT * FROM employees
    UNION ALL
    SELECT * FROM extra_so_users
)

SELECT
    *
FROM combined
WHERE email LIKE '%@%._%'
  AND email NOT LIKE '%/%'
  AND NOT COALESCE(so_deleted, FALSE)
  -- Sesam's user-forvalter/user-powerapp DTL filters never check `retired` — only the
  -- implicit not-deleted filter from the entities API (mirrored by so_deleted above).
  -- Excluding retired here dropped every SO user marked retired=true even when they still
  -- have the Forvalterdashboard interest or a live D365 employee record (confirmed 2026-07-22:
  -- all 80 rows missing vs Sesam's user-forvalter had retired=true).
