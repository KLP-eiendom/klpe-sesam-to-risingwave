{{ config(
    materialized='materialized_view'
) }}

SELECT
    pi.personid                                                     AS "SuperOfficeId",
    u.email                                                         AS "BrukerId",
    pi.persintid                                                    AS "PersIntId",
    pi.name                                                         AS "Name",
    pi.tooltip                                                      AS "Tooltip",
    NULLIF(pi.created, '')::TIMESTAMPTZ                             AS "Registered",
    NULLIF(pi.updated, '')::TIMESTAMPTZ                             AS "Updated"
FROM {{ ref('stg_superoffice_personinterest') }} pi
INNER JOIN {{ ref('mrt_superoffice_user') }} u ON pi.personid = u.personid
WHERE u.email IS NOT NULL
