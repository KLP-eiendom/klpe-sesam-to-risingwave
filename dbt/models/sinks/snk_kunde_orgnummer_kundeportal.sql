{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Kunde_Orgnummer',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'OrgNummer'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY orgnr ORDER BY contactId DESC NULLS LAST) AS rn
    FROM {{ ref('mrt_global_customer') }}
    -- Sesam kunde-orgnummer-kundeportal writes OrgNummer = superoffice-contact:orgnr (the bare/spaced
    -- SO org number), NOT the d365 MVA registration number. The mart's `orgnr` column is that exact SO
    -- field (COALESCE(so_contact.orgnr, so_contactsimple.orgnr)); `mva_nummer` is COALESCE(d365.mva_nummer,
    -- so.orgnr) and emits dirty keys like 'NO840799522MVA' / despaced '964825726' that never match Sesam.
    -- Keying on `orgnr` also drops d365-only customers (orgnr NULL) that Sesam never emits, and guarantees
    -- a non-null SoContactId (orgnr only exists on SO-driven rows). The navn / Utgått filters mirror the
    -- pipe's KundeNavn-non-empty and `not matches *Utgått* category` conditions.
    WHERE (orgnr IS NOT NULL AND orgnr != '')
      AND (kundenummer IS NOT NULL AND kundenummer != '')
      AND (navn IS NOT NULL AND navn != '')
      AND (category IS NULL OR category NOT ILIKE '%utgått%')
      -- Mirrors Sesam's independent Utgått-check on both superoffice-contact:category
      -- and superoffice-contactsimple:category — category alone only covers contactsimple.
      AND (contactCategory IS NULL OR contactCategory NOT ILIKE '%utgått%')
)

SELECT
        {{ test_id("kundenummer") }}
    kundenummer AS "KundeNummer",
    navn        AS "KundeNavn",
    orgnr       AS "OrgNummer",
    contactid   AS "SoContactId",
    '1970-01-01 00:00:00'::TIMESTAMP AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP AS "LastUpdated"
FROM ranked
-- Multiple distinct customer entities occasionally share the same orgnr (subsidiaries under one
-- legal org number, legacy/duplicate SO contacts). The target Kunde_Orgnummer table's upsert key
-- is OrgNummer alone, so without a dedup RW's own upsert silently overwrites with whichever row
-- streams in last (non-deterministic). Keep the lowest contactId (oldest SO contact) — verified
-- against live Sesam output: Sesam's merge consistently keeps the earliest-created contact.
WHERE rn = 1
