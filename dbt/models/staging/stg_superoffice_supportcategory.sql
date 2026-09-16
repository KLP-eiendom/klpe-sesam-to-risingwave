{{ config(
    materialized='table_with_connector'
) }}

/*
  SuperOffice support categories (sakunderkategoriSync).
  These are the "support" type ticket categories — Kantine, Lys, Renhold, etc.
  Distinct from stg_superoffice_ticketcategory which holds "property" type categories.

  Sesam source: superoffice-supportcategory pipe, system="superoffice",
  url="&includeId=sakunderkategoriSync".

  KDI API EntityPath: verify with KDI API team — likely superoffice/supportcategory/items
  or equivalent. The Sesam URL used a named SuperOffice list (sakunderkategoriSync)
  which may be exposed differently through the KDI gateway.

  _id constructed by poller: concat(string(id), "-superoffice-support")
  Matches the Sesam _id pattern: concat(string(id), "-", "superoffice", "-", "support")
*/

CREATE TABLE {{ this }} (
    _id     VARCHAR         PRIMARY KEY,
    id      BIGINT,
    name    VARCHAR
);
