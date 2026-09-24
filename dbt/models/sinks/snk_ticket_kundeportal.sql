{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Sak',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'EksternSakId'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for ticket data to Kundeportal.
  Mirrors Sesam ticket-kundeportal-endpoint.

  Source: mrt_global_ticket (SuperOffice ticket webhook).

  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_DB             Kundeportal database name

  Sesam fields: Created, LastUpdated, EksternSakId, SakskategoriId, Emne,
                Status, OpprettetAv, LukketDato, KundeNummer, SoContactId

*/

SELECT
    {{ test_id("t.ticketid") }}
    t.createdat                             AS "Created",
    t.lastchanged                           AS "LastUpdated",
    t.ticketid::VARCHAR || ':superoffice-ticket' AS "EksternSakId",
    t.title                                 AS "Emne",
    t.ticketstatusid::VARCHAR               AS "Status",
    COALESCE(LOWER(u.email), t.author)      AS "OpprettetAv",
    COALESCE(tc."Id", 0)                    AS "SakskategoriId",
    CASE
        WHEN t.closedat = '0001-01-01 00:00:00+00'::TIMESTAMPTZ THEN NULL
        ELSE t.closedat
    END                                     AS "LukketDato",
    t.contactid                             AS "SoContactId",
    c.kundenummer                           AS "KundeNummer"
FROM {{ ref('mrt_superoffice_ticket') }} t
LEFT JOIN {{ ref('mrt_global_customer') }} c ON t.contactid = c.contactid
LEFT JOIN {{ ref('mrt_superoffice_user') }} u ON t.personId = u.personId
LEFT JOIN {{ ref('mrt_global_ticketcategory') }} tc
    ON t.ticketcategoryid = tc.SakskategoriId
    AND tc.System = 'superoffice'
    AND tc.Type = 'property'
WHERE t.ticketid IS NOT NULL
