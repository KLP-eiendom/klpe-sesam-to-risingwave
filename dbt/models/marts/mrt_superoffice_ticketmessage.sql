{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam superoffice-ticketmessage pipe: emit_children on TicketMessages[]
  from stg_superoffice_ticket webhook.

  Sesam used the REST API poller for this (which included nested TicketMessages[]).
  In RisingWave the ticket data arrives via webhook — the same TicketMessages[] array
  is present when the webhook delivers a full ticket object.

  ExternalId convention: "<EjMessageId>:superoffice-ticketmessage"
  ParentTicketId:        "<TicketId>:superoffice-ticket"

  Field names in TicketMessages[] are PascalCase (Sesam poller convention):
    EjMessageId, Body, HtmlBody, CreatedAt, Slevel, Type, Author,
    Person (object), CreatedBy (object), Attachments (array),
    MessageCategory, MessageId

  Note: If the webhook payload does not include TicketMessages[], this MV will be empty
  until the webhook configuration is updated to include nested messages.
*/

WITH expanded AS (
    SELECT
        (COALESCE(msg->>'EjMessageId', msg->>'ejMessageId'))::BIGINT                 AS ticketMessageId,
        (COALESCE(msg->>'EjMessageId', msg->>'ejMessageId'))::VARCHAR || ':superoffice-ticketmessage'
                                                                    AS externalId,
        t.ticketId                                                  AS ticketId,
        t.ticketId::VARCHAR || ':superoffice-ticket'                AS parentTicketId,
        (COALESCE(msg->>'CreatedAt', msg->>'createdAt'))::TIMESTAMPTZ              AS createdAt,
        COALESCE(msg->>'HtmlBody', msg->>'htmlBody')                                AS htmlBody,
        COALESCE(msg->>'Body', msg->>'body')                                        AS body,
        COALESCE(msg->>'Slevel', msg->>'slevel')                                    AS slevel,
        COALESCE(msg->>'Type', msg->>'type')                                        AS type,
        COALESCE(msg->>'Author', msg->>'author')                                    AS author,
        COALESCE(msg->>'MessageCategory', msg->>'messageCategory')                  AS messageCategory,
        COALESCE(msg->>'MessageId', msg->>'messageId')                              AS messageId,
        COALESCE(
            (COALESCE(msg->'CreatedBy', msg->'createdBy')->>'PersonId')::BIGINT,
            (COALESCE(msg->'CreatedBy', msg->'createdBy')->>'personId')::BIGINT,
            (COALESCE(msg->'Person', msg->'person')->>'PersonId')::BIGINT,
            (COALESCE(msg->'Person', msg->'person')->>'personId')::BIGINT
        )                                                           AS personId,
        COALESCE(
            COALESCE(msg->'CreatedBy', msg->'createdBy')->>'FullName',
            COALESCE(msg->'CreatedBy', msg->'createdBy')->>'fullName'
        )                                                           AS createdByName,
        COALESCE(msg->'Attachments', msg->'attachments')            AS ticketAttachments,
        FALSE                                                       AS _deleted
    FROM {{ ref('mrt_superoffice_ticket') }} t,
    jsonb_array_elements(
        CASE WHEN jsonb_typeof(t.ticketMessages) = 'array' THEN t.ticketMessages ELSE '[]'::JSONB END
    ) AS msg
    WHERE (COALESCE(msg->>'EjMessageId', msg->>'ejMessageId'))::BIGINT IS NOT NULL
),

latest AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY ticketMessageId
            -- If the same message appears in multiple tickets (dirty test data),
            -- prefer the 'Internal' one to ensure it gets filtered by the sink.
            ORDER BY (CASE WHEN slevel = 'Internal' THEN 1 ELSE 2 END) ASC
        ) AS rn
    FROM expanded
)

SELECT
    ticketMessageId,
    externalId,
    ticketId,
    parentTicketId,
    createdAt,
    htmlBody,
    body,
    slevel,
    type,
    author,
    messageCategory,
    messageId,
    personId,
    createdByName,
    ticketAttachments,
    _deleted
FROM latest
WHERE rn = 1
