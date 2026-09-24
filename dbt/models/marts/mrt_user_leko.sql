{{ config(
    materialized='materialized_view'
) }}

/*
  Materialized view for user data to Leko.
  Source for snk_user_leko and queried by RisingWave Data API.
*/

SELECT
    {{ test_id("u.personid") }}
    u.personid                                                          AS "id",
    u.contactid                                                         AS "companyId",
    NULLIF(c.kundenummer, '')                                           AS "companyNumber",
    LOWER(u.email)                                                      AS "email",
    u.firstname                                                         AS "firstName",
    u.lastname                                                          AS "lastName",
    (u.retired OR u._deleted)                                           AS "deleted",
    u.personUpdatedDate                                                 AS "updatedAt",
    u.personRegisteredDate                                              AS "createdAt",
    COALESCE(u.mobilephone, '')                                         AS "phone",
    CASE WHEN u.personinterestids::TEXT ILIKE '%kundeportal%'
         THEN TRUE ELSE FALSE END                                       AS "hasCustomerPortalInterest",
    CASE WHEN u.personinterestids::TEXT ILIKE '%kontraktsansvarlig%'
         THEN TRUE ELSE FALSE END                                       AS "isContractResponsible",
    u.registered                                                        AS "Created",
    u.updated                                                           AS "LastUpdated"
FROM {{ ref('mrt_superoffice_user') }} u
LEFT JOIN {{ ref('mrt_global_customer') }} c ON u.contactid = c.contactid
WHERE (u.contactid IS NOT NULL OR u._deleted OR u.retired)
  AND u.email LIKE '%@%.%'
  AND u.email NOT LIKE '%/%'
