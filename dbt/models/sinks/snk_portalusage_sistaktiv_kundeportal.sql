{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('KUNDEPORTAL_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('KUNDEPORTAL_MYSQL_PORT', '3306') ~ '/' ~ env_var('KUNDEPORTAL_MYSQL_DB', 'kundeportal-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('KUNDEPORTAL_MYSQL_USER', ''),
        'password': env_var('KUNDEPORTAL_MYSQL_PASSWORD', ''),
        'table.name': 'KundeAktivitet',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Kundenummer'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

SELECT
        {{ test_id("p.kundenummer") }}
    p.kundenummer AS "Kundenummer",
    c.contactid::VARCHAR AS "SoContactId",
    p.sist_aktivitet_dato AS "SistAktivDato"
FROM {{ ref('stg_influx_portalusage_sistaktiv') }} p
LEFT JOIN {{ ref('mrt_global_customer') }} c
    ON c.kundenummer = p.kundenummer
WHERE p.kundenummer IS NOT NULL
  AND p.kundenummer != ''
  AND p.sist_aktivitet_dato IS NOT NULL
