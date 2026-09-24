{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Saksmelding',
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
  MySQL sink for ticket message data to Kundeportal.
  Mirrors Sesam ticketmessage-kundeportal-endpoint.

  Source: mrt_global_ticketmessage (via mrt_superoffice_ticketmessage_update webhook).

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_MYSQL_DB       Kundeportal database name

  Sesam fields: EksternId, EksternSakId, Melding, Created, OpprettetAv

  Filter: Slevel != 'Internal' (only public messages) and not deleted.
*/

SELECT
    {{ test_id("COALESCE(upd.ticketmessageid, poll.ticketmessageid)") }}
    COALESCE(poll.externalid, upd.externalid)                           AS "EksternId",
    COALESCE(
        poll.parentticketid,
        upd.parentticketid,
        upd.ticketid::VARCHAR || ':superoffice-ticket'
    )                                                                   AS "EksternSakId",
    COALESCE(NULLIF(COALESCE(poll.htmlbody, upd.htmlbody), ''),
             COALESCE(poll.body, upd.body))                             AS "Melding",
    COALESCE(COALESCE(poll.createdat, upd.createdat)::TIMESTAMP,
             '1970-01-01 00:00:00'::TIMESTAMP)                          AS "Created",
    COALESCE(COALESCE(poll.createdat, upd.createdat)::TIMESTAMP,
             '1970-01-01 00:00:00'::TIMESTAMP)                          AS "LastUpdated",
    COALESCE(u.email, COALESCE(poll.personid, upd.personid)::VARCHAR)   AS "OpprettetAv"
FROM {{ ref('mrt_superoffice_ticketmessage_update') }} AS upd
FULL OUTER JOIN {{ ref('mrt_superoffice_ticketmessage') }} AS poll
    ON upd.ticketmessageid = poll.ticketmessageid
LEFT JOIN {{ ref('mrt_superoffice_user') }} u
    ON COALESCE(poll.personid, upd.personid) = u.personId
WHERE COALESCE(poll.slevel, upd.slevel) != 'Internal'
  AND (COALESCE(upd._deleted, poll._deleted) IS NULL
       OR COALESCE(upd._deleted, poll._deleted) = FALSE)
  AND COALESCE(poll.externalid, upd.externalid) IS NOT NULL
