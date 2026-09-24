{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'ProsjektBilag',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

SELECT
        {{ test_id("_id") }}
    _id               AS "Id",
    prosjekt_id       AS "ProsjektId",
    kategori_id       AS "KategoriId",
    kategorigruppe_id AS "KategorigruppeId",
    bilag             AS "BilagId",
    konto_id          AS "KontoId",
    bilagsdato        AS "BilagDato",
    belop_firmavaluta AS "BelopFirmavaluta",
    belop_fastvaluta  AS "BelopFastvaluta",
    aktivert_kostnad  AS "AktivertKostnadsfort",
    mva               AS "Mva",
    beskrivelse       AS "BilagTekst"
FROM {{ ref('stg_d365_prosjektbilag') }}
WHERE _id IS NOT NULL
