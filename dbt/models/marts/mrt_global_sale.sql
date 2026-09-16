{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-sale.
  FULL OUTER JOIN of superoffice-sale (poller, priority) and superoffice-salesimple (webhook).

  Sesam merge strategy: compact, identity=first
    → Poller takes priority; webhook fills gaps and provides real-time updates
      for sales not yet included in the next poller run.

  Join key: saleId (= Sesam ExternalId)

  Type notes (poller stores many dates and booleans as VARCHAR):
    date, nextDueDate, registeredDate, updatedDate  → VARCHAR in poller, TIMESTAMPTZ in webhook
    completed                                        → VARCHAR in poller, BOOLEAN in webhook
    probPercent                                      → DOUBLE PRECISION in poller and webhook
    NULLIF(..., '') prevents empty strings from failing the TIMESTAMPTZ cast.
*/

SELECT
    CAST(COALESCE(s.saleId,      ss.saleId) AS VARCHAR)      AS saleId,
    CONCAT(COALESCE(s.saleId, ss.saleId)::VARCHAR, ':superoffice-sale') AS externalId,
    COALESCE(s.heading,     ss.heading)     AS heading,
    COALESCE(s.description, ss.description) AS description,
    s.text                                  AS text,
    COALESCE(s.amount,      ss.amount)      AS amount,
    COALESCE(s.earning,     ss.earning)     AS earning,
    COALESCE(s.earningPercent, ss.earningPercent) AS earningPercent,
    COALESCE(s.probPercent, ss.probPercent) AS probPercent,
    COALESCE(s.currency,    ss.currency)    AS currency,
    COALESCE(s.currencyId,  ss.currencyId)  AS currencyId,
    COALESCE(s.saleStatus,  ss.saleStatus)  AS saleStatus,
    COALESCE(s.saleType,    ss.saleType)    AS saleType,
    COALESCE(s.type,        ss.type)        AS type,
    COALESCE(s.stage,       ss.stage)       AS stage,
    COALESCE(s.source,      ss.source)      AS source,
    COALESCE(s.saleNumber,  ss.saleNumber)  AS saleNumber,
    COALESCE(s.associateId, ss.associateId) AS associateId,
    COALESCE(s.contactId,   ss.contactId)   AS contactId,
    COALESCE(s.personId,    ss.personId)    AS personId,
    COALESCE(s.projectId,   ss.projectId)   AS projectId,
    COALESCE(s.projectName, ss.projectName, pj.name) AS projectName,
    COALESCE(s.activeErpLinks, ss.activeErpLinks) AS activeErpLinks,
    COALESCE(s.hasGuide,    ss.hasGuide)    AS hasGuide,
    COALESCE(s.hasQuote,    ss.hasQuote)    AS hasQuote,
    COALESCE(s.hasStakeholders, ss.hasStakeholders) AS hasStakeholders,
    COALESCE(NULLIF(s.completed, '')::BOOLEAN, ss.completed) AS completed,

    -- Date fields: poller stores as VARCHAR, webhook mart as TIMESTAMPTZ
    COALESCE(NULLIF(s.date, '')::TIMESTAMPTZ,          ss.date)          AS date,
    COALESCE(NULLIF(s.nextDueDate, '')::TIMESTAMPTZ,   ss.nextDueDate)   AS nextDueDate,
    COALESCE(NULLIF(s.registeredDate, '')::TIMESTAMPTZ, ss.registeredDate, '1970-01-01 00:00:00'::TIMESTAMPTZ) AS registeredDate,
    COALESCE(NULLIF(s.updatedDate, '')::TIMESTAMPTZ,   ss.updatedDate,   '1970-01-01 00:00:00'::TIMESTAMPTZ) AS updatedDate,

    COALESCE(s.registeredBy, ss.registeredBy) AS registeredBy,
    COALESCE(s.updatedBy,    ss.updatedBy)    AS updatedBy,

    -- Poller-only fields (not available in webhook payload)
    s.visibleFor,
    s.competitor,
    s.lossReason,
    s.credited,
    s.userGroup,
    s.stalledComment,
    s.soldReason,
    s.reOpenDate,
    s.originalStage,
    s.who,
    s.icon,
    s.primaryKey,
    s.entityName,

    -- Observability: which system is the source for this record
    CASE WHEN s.saleId IS NOT NULL THEN 'poller' ELSE 'webhook' END AS _source

FROM {{ ref('stg_superoffice_sale') }} s
FULL OUTER JOIN {{ ref('mrt_superoffice_salesimple') }} ss
    ON s.saleId = ss.saleId
-- Resolve ProsjektNavn from the project: sale entities carry projectId but not the name,
-- mirroring Sesam global-sale's hop to global-project on projectId -> project name.
LEFT JOIN {{ ref('mrt_global_project') }} pj
    ON COALESCE(s.projectId, ss.projectId)::VARCHAR = pj.projectId::VARCHAR
