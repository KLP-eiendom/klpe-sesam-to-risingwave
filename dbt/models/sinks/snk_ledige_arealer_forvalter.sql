{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'LedigAreal',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

SELECT
        {{ test_id("COALESCE(grunn_id,'') || '-' || COALESCE(sone_id,'') || '-' || COALESCE(leieobjekt_id,'') || '-' || COALESCE(areal_type,'') || '-' || COALESCE(kontrakt_id,'')") }}
    COALESCE(grunn_id,'') || '-' || COALESCE(sone_id,'') || '-' || COALESCE(leieobjekt_id,'') || '-' || COALESCE(areal_type,'') || '-' || COALESCE(kontrakt_id,'') AS "Id",
    '2024-01-01 00:00:00'::TIMESTAMP AS "Created",
    -- mirrors Sesam d365-areas.unique_eiendom_id: fall back to grunn_id when the area
    -- has no specific building (bygg_id = '-'), else use bygg_id; UPPER-cased.
    UPPER(CASE WHEN bygg_id = '-' THEN grunn_id ELSE bygg_id END) AS "ByggId",
    grunn_id                AS "GrunnId",
    sone_id                 AS "SoneId",
    leieobjekt_id           AS "LeieobjektId",
    areal_type              AS "ArealType",
    areal_type_navn         AS "ArealTypeNavn",
    etasje                  AS "Etasje",
    ledig_areal             AS "LedigArealM2",
    markedspris_ledig_areal AS "MarkedsprisLedigAreal",
    markedspris_pr_m2       AS "MarkedsprisPerM2",
    sone_beskrivelse        AS "SoneBeskrivelse",
    sone_nummer             AS "SoneNummer",
    fysisk_areal            AS "FysiskArealM2"
FROM {{ ref('stg_d365_areas') }}
WHERE areal_type NOT IN ('EFA', 'BFA', 'MFA', 'NRA')
  AND _id IS NOT NULL
  AND kontrakt_id = '-'
