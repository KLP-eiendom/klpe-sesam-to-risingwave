{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam prosjekt-juridiskselskap-superoffice.
  Links SuperOffice projects to legal entities (Juridisk Selskap) based on the building ID
  prefix in the project name (first 6 characters).

  Source: mrt_global_project
  Join: mrt_global_property ON substring(project.name, 1, 6) = property.bygg_avdeling_id
*/

SELECT
    p.projectId,
    p.name                                                              AS "projectName",
    p.type                                                              AS "projectType",
    prop.bf_firma_navn                                                  AS "navn",
    prop.bf_orgnummer                                                   AS "orgnummer",
    prop."GnrBnr"                                                       AS "gaardbruksnummer",
    prop.b_adresse                                                      AS "adresse"
FROM {{ ref('mrt_global_project') }} p
LEFT JOIN {{ ref('mrt_global_property') }} prop
    ON SUBSTRING(p.name, 1, 6) = prop.bygg_avdeling_id
WHERE p.projectId IS NOT NULL
  AND p.projectId != 0
  AND LOWER(p.type) LIKE '%eiendom%'
