{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'SakSakskategori',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'EksternSakId,SakskategoriId'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  MySQL sink for ticket support category junction to Kundeportal.
  Mirrors Sesam ticketsupportcategory-kundeportal-endpoint → table SakSakskategori.

  Source: mrt_superoffice_ticket (CustomFields.x_kategori) + mrt_global_ticketcategory (Type='support').

  Primary key in Kundeportal: (EksternSakId, SakskategoriId)
*/

SELECT
    {{ test_id("t.ticketid::VARCHAR || ':superoffice-ticket'") }}
    t.ticketid::VARCHAR || ':superoffice-ticket'     AS "EksternSakId",
    tc."Id"                                          AS "SakskategoriId",
    t.createdat                                      AS "Created",
    t.lastchanged                                    AS "LastUpdated"
FROM {{ ref('mrt_superoffice_ticket') }} t
JOIN {{ ref('mrt_global_ticketcategory') }} tc
    ON t.supportcategoryname = tc.navn
   AND tc.type = 'support'
WHERE tc."Id" IS NOT NULL
