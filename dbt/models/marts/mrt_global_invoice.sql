{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-invoice, collapsing d365-faktura-detaljer-with-commonid.

  Sesam intermediate d365-faktura-detaljer-with-commonid computed:
    CommonId = UPPER(concat(firma_id, "-", kunde_nummer, "-", faktura_nummer))
  This is computed inline here rather than as a separate model.

  Source: stg_d365_faktura_detaljer (BigQuery Datavarehus.faktura_detaljer).
*/

SELECT
    *,
    UPPER(CONCAT(firma_id, '-', kunde_nummer, '-', faktura_nummer)) AS CommonId,
    '1970-01-01 00:00:00'::TIMESTAMP AS "Created",
    '1970-01-01 00:00:00'::TIMESTAMP AS "LastUpdated"

FROM {{ ref('stg_d365_faktura_detaljer') }}
