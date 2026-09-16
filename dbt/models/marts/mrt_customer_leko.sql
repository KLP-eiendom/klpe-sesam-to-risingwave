{{ config(
    materialized='materialized_view'
) }}

/*
  Materialized view for customer data to Leko.
  Source for snk_customer_leko and queried by RisingWave Data API.
*/

SELECT
    {{ test_id("contactId") }}
    contactId                               AS "Id",
    kundenummer                             AS "number",
    contactSimpleName                       AS "name",
    streetAddress                           AS "address",
    postalAddress                           AS "postalAddress",
    invoiceAddress                          AS "invoiceAddress",
    department                              AS "department",
    description                             AS "description",
    orgnr                                   AS "orgNumber",
    kontakt_tlf                             AS "phone",
    updatedDate                             AS "updatedAt",
    registeredDate                          AS "createdAt"
FROM {{ ref('mrt_global_customer') }}
WHERE contactId IS NOT NULL
  AND (category IS NULL OR category NOT LIKE '%Utgått%')
