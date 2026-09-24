{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-customer.
  Joins D365 customer master with SuperOffice contacts.
  Primary join: so_contact.number = d365.kundenummer (Sesam d365-kundenummer-ni equality).
  D365 customers without a matching SO contact are included as kundenummer-only rows.
*/

WITH d365 AS (
    SELECT
        kundenummer,
        navn,
        navn_alias,
        adresse,
        gate_adresse,
        postnummer,
        by,
        region_id,
        kontakt_tlf,
        kontakt_epost,
        kundegruppe,
        kundegruppe_navn,
        mva_nummer,
        opprettet_dato
    FROM {{ ref('stg_d365_kunde') }}
),

so_unified AS (
    WITH so_c AS (
        SELECT
            contactId, number, nameDepartment, orgnr, registeredDate, updatedDate, category, business, country, stop, urlURLAddress
        FROM {{ ref('stg_superoffice_contact') }}
        WHERE contactId > 0
          AND nameDepartment IS NOT NULL
          AND TRIM(nameDepartment) != ''
    ),
    so_cs AS (
        SELECT
            contactId, number, name, nameDepartment, emailAddress, city, url, category, isOwnerContact, contactPhoneFormattedNumber, orgnr, business,
            department, description, invoiceAddress, streetAddress, postalAddress, registeredDate, updatedDate, country, stop
        FROM {{ ref('mrt_superoffice_contactsimple') }}
        WHERE contactId > 0
          AND nameDepartment IS NOT NULL
          AND TRIM(nameDepartment) != ''
    )
    SELECT
        COALESCE(so_cs.contactId, so_c.contactId)                                 AS contactid,
        COALESCE(NULLIF(so_cs.number, ''), NULLIF(so_c.number, ''))               AS number,
        COALESCE(NULLIF(so_cs.nameDepartment, ''), NULLIF(so_c.nameDepartment, '')) AS namedepartment,
        -- Bare navn uten avdeling, brukt av customer-leko (mirrors Sesam coalesce(contactsimple:name, contact:nameDepartment))
        COALESCE(NULLIF(so_cs.name, ''), NULLIF(so_c.nameDepartment, ''))         AS contactsimplename,
        COALESCE(NULLIF(so_cs.orgnr, ''), NULLIF(so_c.orgnr, ''))                 AS orgnr,
        COALESCE(so_cs.registeredDate, so_c.registeredDate)                       AS registeredDate,
        COALESCE(so_cs.updatedDate, so_c.updatedDate)                             AS updatedDate,
        COALESCE(NULLIF(so_cs.category, ''), NULLIF(so_c.category, ''))           AS category,
        -- Kept separate from `category` (mirrors Sesam's independent Utgått-check on both
        -- superoffice-contact:category and superoffice-contactsimple:category)
        so_c.category                                                             AS contactCategory,
        COALESCE(NULLIF(so_cs.business, ''), NULLIF(so_c.business, ''))           AS business,
        COALESCE(NULLIF(so_cs.country, ''), NULLIF(so_c.country, ''))             AS country,
        COALESCE(so_cs.stop, so_c.stop)                                           AS stop,
        so_cs.emailAddress,
        so_cs.city,
        COALESCE(NULLIF(so_cs.url, ''), NULLIF(so_c.urlURLAddress, ''))           AS url,
        so_cs.isOwnerContact,
        so_cs.contactPhoneFormattedNumber,
        so_cs.department,
        so_cs.description,
        so_cs.invoiceAddress,
        so_cs.streetAddress,
        so_cs.postalAddress
    FROM so_c
    FULL OUTER JOIN so_cs ON so_c.contactId = so_cs.contactId
),

consolidated AS (
    -- SO contacts drive primary rows; D365 joined by SO.number = D365.kundenummer
    -- (mirrors Sesam equality: d-k.$ids = s-c.d365-kundenummer-ni)
    SELECT
        s.contactid,
        s.number,
        COALESCE(d.kundenummer, s.number) AS kundenummer
    FROM so_unified s
    LEFT JOIN d365 d
        ON d.kundenummer = s.number
        AND s.number IS NOT NULL
        AND s.number != ''

    UNION ALL

    -- D365 customers with no matching SO contact
    SELECT
        NULL::BIGINT AS contactid,
        NULL         AS number,
        d.kundenummer
    FROM d365 d
    WHERE NOT EXISTS (
        SELECT 1 FROM so_unified s
        WHERE s.number = d.kundenummer
          AND s.number IS NOT NULL
          AND s.number != ''
    )
)

SELECT
    c.kundenummer,
    COALESCE(d.navn, s.namedepartment) AS navn,
    d.navn_alias,
    d.adresse,
    d.gate_adresse,
    d.postnummer,
    COALESCE(d.by, s.city) AS "by",
    d.region_id,
    COALESCE(d.kontakt_tlf, s.contactPhoneFormattedNumber) AS kontakt_tlf,
    COALESCE(d.kontakt_epost, s.emailAddress) AS kontakt_epost,
    d.kundegruppe,
    d.kundegruppe_navn,
    COALESCE(d.mva_nummer, s.orgnr) AS mva_nummer,
    d.opprettet_dato,
    -- SuperOffice fields
    s.contactid AS contactId,
    s.namedepartment AS nameDepartment,
    s.contactsimplename AS contactSimpleName,
    s.orgnr,
    s.registeredDate,
    s.updatedDate,
    s.category,
    s.contactCategory,
    s.business,
    s.country,
    s.emailAddress,
    s.city,
    s.url,
    s.isOwnerContact,
    s.stop,
    -- SO address fields for Leko sink
    s.streetAddress,
    s.postalAddress,
    s.invoiceAddress,
    s.department,
    s.description,
    -- Timestamps
    COALESCE(s.registeredDate, d.opprettet_dato, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    COALESCE(s.updatedDate, d.opprettet_dato, '1970-01-01 00:00:00'::TIMESTAMP)    AS "LastUpdated"
FROM consolidated c
LEFT JOIN d365 d ON c.kundenummer = d.kundenummer
LEFT JOIN so_unified s ON c.contactid = s.contactid
