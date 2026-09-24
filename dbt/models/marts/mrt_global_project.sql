{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-project.
  FULL OUTER JOIN of superoffice-project (poller, priority) and superoffice-projectsimple (webhook).

  Sesam merge strategy: compact, identity=first
    → Poller takes priority; webhook fills gaps and provides real-time updates
      for projects not yet included in the next poller run.

  Join key: projectId (= Sesam ExternalId)
*/

SELECT
    COALESCE(p.projectId,   ps.projectId)   AS projectId,
    COALESCE(p.name,        ps.name)         AS name,
    COALESCE(p.text,        ps.text)         AS text,
    COALESCE(p.description, ps.description)  AS description,
    COALESCE(p.number,      ps.number)       AS number,
    COALESCE(p.type,        ps.type)         AS type,
    COALESCE(p.status,      ps.status)       AS status,
    COALESCE(p.associateId, ps.associateId)  AS associateId,
    COALESCE(p.hasGuide,    ps.hasGuide)     AS hasGuide,
    COALESCE(p.hasInfoText, ps.hasInfoText)  AS hasInfoText,
    COALESCE(p.completed,   ps.completed)    AS completed,

    -- Date fields: poller stores VARCHAR, webhook mart casts to TIMESTAMPTZ.
    -- NULLIF handles empty strings from the poller before casting.
    COALESCE(NULLIF(p.endDate, '')::TIMESTAMPTZ,       ps.endDate)        AS endDate,
    COALESCE(NULLIF(p.nextMilestone, '')::TIMESTAMPTZ, ps.nextMilestone)  AS nextMilestone,
    COALESCE(NULLIF(p.registeredDate, '')::TIMESTAMPTZ, ps.registeredDate) AS registeredDate,
    COALESCE(NULLIF(p.updatedDate, '')::TIMESTAMPTZ,   ps.updatedDate)    AS updatedDate,

    COALESCE(p.registeredBy, ps.registeredBy) AS registeredBy,
    COALESCE(p.updatedBy,    ps.updatedBy)    AS updatedBy,

    -- Poller-only fields (richer metadata not available in webhook payload)
    p.icon,
    COALESCE(p.userDefinedFields, ps.userDefinedFields) AS userDefinedFields,
    p.primaryKey,
    p.entityName,

    -- Observability: which system is the source for this record
    CASE WHEN p.projectId IS NOT NULL THEN 'poller' ELSE 'webhook' END AS _source

FROM {{ ref('stg_superoffice_project') }} p
FULL OUTER JOIN {{ ref('mrt_superoffice_projectsimple') }} ps
    ON p.projectId = ps.projectId
