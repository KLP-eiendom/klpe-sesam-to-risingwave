{{ config(
    materialized='materialized_view'
) }}

SELECT
    (payload->>'saleId')::BIGINT                    AS saleId,
    payload->>'heading'                             AS heading,
    payload->>'description'                         AS description,
    (payload->>'amount')::DOUBLE PRECISION          AS amount,
    (payload->>'earning')::DOUBLE PRECISION         AS earning,
    (payload->>'earningPercent')::DOUBLE PRECISION  AS earningPercent,
    (payload->>'probPercent')::DOUBLE PRECISION     AS probPercent,
    payload->>'currency'                            AS currency,
    (payload->>'currencyId')::BIGINT                AS currencyId,
    payload->>'saleStatus'                          AS saleStatus,
    payload->>'saleType'                            AS saleType,
    payload->>'type'                                AS type,
    payload->>'stage'                               AS stage,
    payload->>'source'                              AS source,
    payload->>'saleNumber'                          AS saleNumber,
    (payload->>'date')::TIMESTAMPTZ                 AS date,
    (payload->>'nextDueDate')::TIMESTAMPTZ          AS nextDueDate,
    (payload->>'registeredDate')::TIMESTAMPTZ       AS registeredDate,
    (payload->>'updatedDate')::TIMESTAMPTZ          AS updatedDate,
    payload->>'registeredBy'                        AS registeredBy,
    payload->>'updatedBy'                           AS updatedBy,
    payload->>'associateId'                         AS associateId,
    (payload->>'contactId')::BIGINT                 AS contactId,
    (payload->>'personId')::BIGINT                  AS personId,
    (payload->>'projectId')::BIGINT                 AS projectId,
    payload->>'projectName'                         AS projectName,
    (payload->>'activeErpLinks')::BOOLEAN           AS activeErpLinks,
    (payload->>'hasGuide')::BOOLEAN                 AS hasGuide,
    (payload->>'hasQuote')::BOOLEAN                 AS hasQuote,
    (payload->>'hasStakeholders')::BOOLEAN          AS hasStakeholders,
    (payload->>'completed')::BOOLEAN                AS completed
FROM {{ ref('stg_superoffice_salesimple') }}
