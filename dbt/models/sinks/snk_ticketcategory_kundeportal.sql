{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'Sakskategori',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'SakskategoriId,System,Type'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for ticket category data to Kundeportal.
  Mirrors Sesam ticketcategory-kundeportal-endpoint → table Sakskategori.

  Source: mrt_global_ticketcategory (SO property + SO support + KP metadata).

  Primary key in Kundeportal: (SakskategoriId, System, Type)
  Applied via EF Core migration 20260326085707_Alter_Table_Sakskategori_Add_UniqueConstraint
  in KundeportalCommonDAL. The migration atomically moves the PK from Id to
  (SakskategoriId, System, Type) while keeping a UNIQUE KEY on Id for the FK
  from SakSakskategori and AUTO_INCREMENT support.
  Required environment variables:
    KUNDEPORTAL_MYSQL_HOST     e.g. localhost
    KUNDEPORTAL_MYSQL_PORT     e.g. 3306
    KUNDEPORTAL_MYSQL_USER     MySQL username
    KUNDEPORTAL_MYSQL_PASSWORD MySQL password
    KUNDEPORTAL_DB             Kundeportal database name

  Sesam fields: Navn, SakskategoriId, Parent, System, Type, Kode, Created, LastUpdated
*/

SELECT
        {{ test_id("(sakskategoriid)::VARCHAR || ':' || system || ':' || type") }}
navn                                            AS "Navn",
    sakskategoriid                                  AS "SakskategoriId",
    parent                                          AS "Parent",
    system                                          AS "System",
    type                                            AS "Type",
    kode                                            AS "Kode",
    created                                         AS "Created",
    lastupdated                                     AS "LastUpdated"
FROM {{ ref('mrt_global_ticketcategory') }}
WHERE sakskategoriid IS NOT NULL
