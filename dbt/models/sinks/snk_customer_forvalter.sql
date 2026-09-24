{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Kunde',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for customer data to Forvalter.
  Mirrors Sesam customer-forvalter-endpoint.

  Source: mrt_global_customer.

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, Nummer, Navn, GateAdresse, PostNummer, By, Epost, Land, SuperOfficeContactId

  Gap vs Sesam:
    Kundegruppe — Sesam's source dataset carries it (D365 mrt_global_customer.kundegruppe
    is available), but the real Forvalter Kunde table (confirmed via live schema, prod)
    has no such column — Id, Nummer, Navn, Epost, PostNummer, By, Land, GateAdresse,
    SuperOfficeContactId only. Sesam's own write must have silently dropped it too, so
    the Tier-2 kundegruppe "diff" is a validator artifact (compares against the Sesam
    source, not what Sesam actually persisted) — do not add this column, JDBC upsert
    would fail against the live table.

  Dedup: the target Kunde table has a unique index (IX_Kunde_Nummer) on Nummer, separate
  from the upsert primary_key (Id). Multiple distinct SO contacts occasionally share the
  same D365 kundenummer (old/legacy contact data, isOwnerContact=false on all — no reliable
  "authoritative contact" signal). Sesam's global-customer merge (strategy=compact) collapses
  these into a single entity; here we keep one row per kundenummer, preferring the highest
  contactId (most recently created SO contact) as a deterministic proxy. Blank-string
  kundenummer values are also excluded (they'd collide on the same unique index).
*/

WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY kundenummer ORDER BY contactId DESC NULLS LAST) AS rn
    FROM {{ ref('mrt_global_customer') }}
    WHERE kundenummer IS NOT NULL AND kundenummer != ''
)

SELECT
        {{ test_id("COALESCE(contactId::TEXT, kundenummer)") }}
COALESCE(contactId::TEXT, kundenummer)                  AS "Id",
    kundenummer                                             AS "Nummer",
    navn                                                    AS "Navn",
    COALESCE(gate_adresse, adresse)                         AS "GateAdresse",
    postnummer                                               AS "PostNummer",
    COALESCE(city, "by")                                    AS "By",
    LEFT(COALESCE(emailAddress, kontakt_epost), 150)         AS "Epost",
    COALESCE(region_id, country)                             AS "Land",
    contactId                                               AS "SuperOfficeContactId"
FROM ranked
WHERE rn = 1
