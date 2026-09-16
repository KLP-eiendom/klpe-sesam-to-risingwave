{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'ProsjektBudsjett',
        'type': 'upsert',
        'force_compaction': 'true',
        'primary_key': 'Id'
    }
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  MySQL sink for project budget data to Forvalter.
  Mirrors Sesam prosjektbudsjett-forvalter-endpoint.

  Source: mrt_global_budget (stg_d365_prosjektbudsjett).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_DB             Forvalter database name

  Sesam fields: Id, FirmaId, KontoId, ByggAvdelingId, KontraktId, Budsjettnummer,
                Budsjettmodell, Budsjettdato, BelopFastValutakurs, BelopFastValutakursPerDato, Kommentar

*/

SELECT
    {{ test_id("COALESCE(prosjekt_id,'') || '-' || COALESCE(konto_id,'') || '-' || COALESCE(bygg_avdeling_id,'') || '-' || COALESCE(kontnadsted_id,'') || '-' || COALESCE(budsjettdato::DATE::VARCHAR,'')") }}
    COALESCE(prosjekt_id,'') || '-' || COALESCE(konto_id,'') || '-' || COALESCE(bygg_avdeling_id,'') || '-' || COALESCE(kontnadsted_id,'') || '-' || COALESCE(budsjettdato::DATE::VARCHAR,'') AS "Id",
    firma_id                    AS "FirmaId",
    konto_id                    AS "KontoId",
    bygg_avdeling_id            AS "ByggAvdelingId",
    budsjettdato                AS "Budsjettdato",
    kontrakt_id                 AS "KontraktId",
    prosjekt_id                 AS "Budsjettnummer",
    budsjettmodell              AS "Budsjettmodell",
    belop_firmavaluta           AS "BelopFastValutakurs",
    belop_valutakors_per_dato   AS "BelopFastValutakursPerDato",
    kommentar                   AS "Kommentar",
    COALESCE(budsjettdato::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "Created",
    COALESCE(budsjettdato::TIMESTAMP, '1970-01-01 00:00:00'::TIMESTAMP) AS "LastUpdated"
FROM {{ ref('stg_d365_prosjektbudsjett') }}
WHERE prosjekt_id IS NOT NULL AND prosjekt_id <> ''
  AND konto_id IS NOT NULL AND konto_id <> '' AND konto_id <> '-'
  AND bygg_avdeling_id IS NOT NULL AND bygg_avdeling_id <> ''
  AND budsjettdato IS NOT NULL
