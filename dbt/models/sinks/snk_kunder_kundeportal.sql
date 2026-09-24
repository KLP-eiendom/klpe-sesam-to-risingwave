{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Kunder',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Kundenummer'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for customer data to Kundeportal.
  Mirrors Sesam kunder-kundeportal-endpoint.
*/

SELECT
        {{ test_id("kundenummer") }}
kundenummer                                             AS "Kundenummer",
    NULLIF(REGEXP_REPLACE(adresse, '[^\u0000-\uFFFF]', '', 'g'), '') AS "Adresse",
    NULLIF(REGEXP_REPLACE(navn_alias, '[^\u0000-\uFFFF]', '', 'g'), '') AS "Alias",
    NULL::VARCHAR                                            AS "EanNummer",
    LEFT(NULLIF(COALESCE(emailAddress, kontakt_epost), ''), 150) AS "Epost",
    NULLIF(kundegruppe, '')                                  AS "Kundegruppe",
    NULLIF(region_id, '')                                    AS "Land",
    REGEXP_REPLACE(navn, '[^\u0000-\uFFFF]', '', 'g')        AS "Navn",
    COALESCE(registeredDate, opprettet_dato)                 AS "OpprettetDato",
    NULLIF(postnummer, '')                                   AS "Postkode",
    LEFT(NULLIF(REGEXP_REPLACE(kontakt_tlf, '[^\u0000-\uFFFF]', '', 'g'), ''), 20) AS "Telefon",
    LEFT(NULLIF(REGEXP_REPLACE(url, '[^\u0000-\uFFFF]', '', 'g'), ''), 100) AS "Url",
    NULL::VARCHAR                                            AS "Valuta",
    NULLIF(REGEXP_REPLACE(navn, '[^\u0000-\uFFFF]', '', 'g'), '') AS "Visningsnavn",
    0                                                        AS "AktivtLeieForhold",
    contactId                                               AS "SoContactId",
    '1970-01-01 00:00:00'::TIMESTAMP                        AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP                        AS "LastUpdated"
FROM {{ ref('mrt_global_customer') }}
WHERE kundenummer IS NOT NULL
  AND (category IS NULL OR category NOT LIKE '%Utgått%')
  -- Mirrors Sesam's independent Utgått-check on both superoffice-contact:category
  -- and superoffice-contactsimple:category — category alone only covers contactsimple.
  AND (contactCategory IS NULL OR contactCategory NOT LIKE '%Utgått%')
  -- Mirrors Sesam's (is-not-null Navn OR Visningsnavn) AND (neq "" ...) filter. navn and
  -- Visningsnavn share the same COALESCE chain here too, so one NULL/empty check covers both
  -- — excludes D365-only customers with no navn in D365 and no SO match to fall back to.
  AND navn IS NOT NULL AND TRIM(navn) != ''
