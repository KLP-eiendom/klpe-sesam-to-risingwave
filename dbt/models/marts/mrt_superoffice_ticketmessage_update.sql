{{ config(
    materialized='materialized_view'
) }}

/*
  Parses the superoffice-ticketmessage-update webhook payload.

  Each webhook event represents an incremental update to a ticket message.
  The payload carries the full message object including ticketAttachments[].

  ExternalId mirrors Sesam's convention: "<ticketMessageId>:superoffice-ticketmessage"

  NOTE: no RW pusher exists yet for this table (the ticketmessage-update flow posts
  to Sesam only; RW is seed-fed). Any future RW push path must send the PK envelope
  {"ticketMessageId": <id>, "payload": {...}}.
*/

SELECT
    (payload->>'ticketMessageId')::BIGINT                       AS ticketMessageId,
    payload->>'_id'                                             AS _id,
    (payload->>'_deleted')::BOOLEAN                             AS _deleted,
    -- Sesam ExternalId convention
    (payload->>'ticketMessageId') || ':superoffice-ticketmessage' AS ExternalId,
    -- Parent ticket linkage
    (payload->>'ticketId')::BIGINT                              AS ticketId,
    payload->>'parentTicketId'                                  AS ParentTicketId,
    -- Message content
    (payload->>'createdAt')::TIMESTAMPTZ                        AS CreatedAt,
    payload->>'htmlBody'                                        AS HtmlBody,
    payload->>'body'                                            AS Body,
    payload->>'slevel'                                          AS Slevel,
    -- Author
    (payload->>'personId')::BIGINT                              AS PersonId,
    payload->>'from'                                            AS FromAddress,
    payload->>'to'                                              AS ToAddress,
    payload->>'cc'                                              AS CcAddress,
    -- Raw attachments array for downstream expansion
    payload->'ticketAttachments'                                AS ticketAttachments
FROM {{ ref('stg_superoffice_ticketmessage_update') }}
