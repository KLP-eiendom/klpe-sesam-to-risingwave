{{ config(
    materialized='materialized_view'
) }}

SELECT
    (payload->>'projectId')::BIGINT                 AS projectId,
    payload->>'name'                                AS name,
    payload->>'text'                                AS text,
    payload->>'description'                         AS description,
    payload->>'number'                              AS number,
    payload->>'type'                                AS type,
    payload->>'status'                              AS status,
    payload->>'associateId'                         AS associateId,
    (payload->>'endDate')::TIMESTAMPTZ              AS endDate,
    (payload->>'nextMilestone')::TIMESTAMPTZ        AS nextMilestone,
    (payload->>'registeredDate')::TIMESTAMPTZ       AS registeredDate,
    (payload->>'updatedDate')::TIMESTAMPTZ          AS updatedDate,
    payload->>'registeredBy'                        AS registeredBy,
    payload->>'updatedBy'                           AS updatedBy,
    (payload->>'completed')::BOOLEAN                AS completed,
    (payload->>'hasGuide')::BOOLEAN                 AS hasGuide,
    (payload->>'hasInfoText')::BOOLEAN              AS hasInfoText,
    payload->>'userDefinedFields'                   AS userDefinedFields
FROM {{ ref('stg_superoffice_projectsimple') }}
