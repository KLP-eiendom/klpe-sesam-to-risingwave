{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'VedleggSak',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'EksternId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for ticket message attachment data to Kundeportal.
  Mirrors Sesam ticketmessageattachment-kundeportal-endpoint.

  Source: same FULL OUTER JOIN as snk_ticketmessage_kundeportal — combines
    mrt_superoffice_ticketmessage_update (webhook, "upd") and
    mrt_superoffice_ticketmessage (ticket-embedded TicketMessages[], "poll").
  Each side's ticketAttachments[] uses its own source's field casing
  (webhook: camelCase; ticket-embedded: PascalCase) — COALESCE both per field.

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_MYSQL_DB       Kundeportal database name

  Sesam fields: EksternId, EksternSaksmeldingId, Type, FileName, FileSize

  Filter: Slevel != 'Internal' (inherited from parent message) and not deleted.

  FileName sanitization: Kundeportal's VedleggSak.FileName column isn't utf8mb4, so
  4-byte UTF-8 characters (emoji, rare supplementary-plane symbols) in an attachment's
  original filename get rejected by the JDBC sink ("Incorrect string value"). Strip
  characters above U+FFFF (the utf8mb3/utf8mb4 boundary) rather than dropping the row.
*/

SELECT
        {{ test_id("COALESCE(att->>'AttachmentId', att->>'attachmentId') || ':superoffice-ticketmessageattachment'") }}
    COALESCE(att->>'AttachmentId', att->>'attachmentId') || ':superoffice-ticketmessageattachment' AS "EksternId",
    COALESCE(poll.externalid, upd.externalid)                              AS "EksternSaksmeldingId",
    COALESCE(att->>'ContentType', att->>'contentType')                     AS "Type",
    regexp_replace(COALESCE(att->>'Name', att->>'name'), '[\x{10000}-\x{10FFFF}]', '', 'g') AS "FileName",
    (COALESCE(att->>'AttSize', att->>'attSize'))::NUMERIC::BIGINT          AS "FileSize",
    COALESCE(COALESCE(poll.createdat, upd.createdat)::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    COALESCE(COALESCE(poll.createdat, upd.createdat)::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated"
FROM {{ ref('mrt_superoffice_ticketmessage_update') }} AS upd
FULL OUTER JOIN {{ ref('mrt_superoffice_ticketmessage') }} AS poll
    ON upd.ticketmessageid = poll.ticketmessageid,
jsonb_array_elements(
    CASE
        WHEN jsonb_typeof(COALESCE(poll.ticketattachments, upd.ticketattachments)) = 'array'
        THEN COALESCE(poll.ticketattachments, upd.ticketattachments)
        ELSE '[]'::JSONB
    END
) AS att
WHERE COALESCE(poll.slevel, upd.slevel) != 'Internal'
  AND (COALESCE(upd._deleted, poll._deleted) IS NULL
       OR COALESCE(upd._deleted, poll._deleted) = FALSE)
  AND COALESCE(poll.externalid, upd.externalid) IS NOT NULL
  AND COALESCE(att->>'AttachmentId', att->>'attachmentId') IS NOT NULL
