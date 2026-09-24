{{ config(
    materialized='materialized_view'
) }}

/*
  Enriches mrt_global_sale with Kundenummer from mrt_global_customer.
  Used by snk_sale_forvalter and snk_sale_kundeportal.

  Join: mrt_global_sale.contactId = mrt_global_customer.contactid
  Kundenummer is NULL when no matching customer exists for the SO contact.

  Department/branch SO contacts (e.g. "Skatteetaten avd Bergen") occasionally
  duplicate a customer's Kundenummer via SuperOffice data quality issues
  (confirmed case: kundenummer 600335 — contactId 8636 is the real company,
  18327 is its Bergen department, both carry the same D365 kundenummer in SO,
  only 8636 is authoritative; Sesam's real merge doesn't resolve Kundenummer
  via the department contact either). We only null out Kundenummer for a
  department contact when a non-department sibling ALSO carries the same
  kundenummer (a proven duplicate) — a contact that merely has a department
  filled in, with no such sibling, is a normal single contact and keeps its
  Kundenummer.
*/

WITH customer_has_primary AS (
    SELECT kundenummer, BOOL_OR(COALESCE(department, '') = '') AS has_primary_contact
    FROM {{ ref('mrt_global_customer') }}
    WHERE kundenummer IS NOT NULL AND kundenummer != ''
    GROUP BY kundenummer
)

SELECT
    s.*,
    CASE
        WHEN COALESCE(c.department, '') != '' AND COALESCE(chp.has_primary_contact, FALSE)
        THEN NULL
        ELSE c.kundenummer
    END AS kundenummer
FROM {{ ref('mrt_global_sale') }} s
LEFT JOIN {{ ref('mrt_global_customer') }} c
    ON s.contactid = c.contactid
LEFT JOIN customer_has_primary chp
    ON chp.kundenummer = c.kundenummer
