{{ config(
    materialized='materialized_view'
) }}

SELECT
    (COALESCE(payload->>'TicketId', payload->>'ticketId'))::BIGINT                     AS ticketId,
    COALESCE(payload->'TicketMessages', payload->'ticketMessages')                    AS ticketMessages,
    COALESCE(payload->>'Title', payload->>'title')                                     AS title,
    COALESCE(payload->>'BaseStatus', payload->>'baseStatus')                           AS baseStatus,
    COALESCE(payload->>'ReadStatus', payload->>'readStatus')                           AS readStatus,
    COALESCE(payload->>'Slevel', payload->>'slevel')                                   AS slevel,
    COALESCE(payload->>'Author', payload->>'author')                                   AS author,
    COALESCE(payload->>'Origin', payload->>'origin')                                   AS origin,
    (COALESCE(payload->>'CreatedAt', payload->>'createdAt'))::TIMESTAMPTZ              AS createdAt,
    (COALESCE(payload->>'LastChanged', payload->>'lastChanged'))::TIMESTAMPTZ          AS lastChanged,
    (COALESCE(payload->>'ClosedAt', payload->>'closedAt'))::TIMESTAMPTZ                AS closedAt,
    (COALESCE(payload->>'Deadline', payload->>'deadline'))::TIMESTAMPTZ                AS deadline,
    (COALESCE(payload->>'NumMessages', payload->>'numMessages'))::BIGINT               AS numMessages,
    (COALESCE(payload->>'NumReplies', payload->>'numReplies'))::BIGINT                 AS numReplies,
    (COALESCE(payload->>'AlertLevel', payload->>'alertLevel'))::BIGINT                 AS alertLevel,
    (COALESCE(payload->>'TimeToClose', payload->>'timeToClose'))::BIGINT               AS timeToClose,
    (COALESCE(payload->>'TimeToReply', payload->>'timeToReply'))::BIGINT               AS timeToReply,
    (COALESCE(payload->>'HasAttachment', payload->>'hasAttachment'))::BOOLEAN           AS hasAttachment,
    (COALESCE(payload->'Person'->>'ContactId', payload->'person'->>'contactId'))::BIGINT AS contactId,
    (COALESCE(payload->'Person'->>'PersonId', payload->'person'->>'personId'))::BIGINT   AS personId,
    COALESCE(payload->'Category'->>'Name', payload->'category'->>'name')               AS categoryName,
    (COALESCE(payload->'Category'->>'TicketCategoryId', payload->'category'->>'ticketCategoryId'))::BIGINT AS ticketCategoryId,
    COALESCE(payload->'Status'->>'Name', payload->'status'->>'name')                   AS statusName,
    (COALESCE(payload->'Status'->>'TicketStatusId', payload->'status'->>'ticketStatusId'))::BIGINT AS ticketStatusId,
    COALESCE(payload->'CustomFields'->>'x_kategori', payload->'customFields'->>'x_kategori') AS supportCategoryName
FROM {{ ref('stg_superoffice_ticket') }}
WHERE COALESCE(payload->>'TicketId', payload->>'ticketId') IS NOT NULL
  AND NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
