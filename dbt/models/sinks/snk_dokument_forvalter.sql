{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink'],
    connector='jdbc',
    connector_parameters={
        'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':' ~ env_var('FORVALTER_MYSQL_PORT', '3306') ~ '/' ~ env_var('FORVALTER_MYSQL_DB', 'forvalter-db-dev') ~ '?nullCatalogMeansCurrent=true',
        'user': env_var('FORVALTER_MYSQL_USER', ''),
        'password': env_var('FORVALTER_MYSQL_PASSWORD', ''),
        'table.name': 'Dokument',
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
  MySQL sink for document data to Forvalter.
  Mirrors Sesam dokument-forvalter-endpoint.

  Source: mrt_global_document (SO document webhook + verified-document + leko-dokument).

  Required environment variables:
    FORVALTER_MYSQL_HOST     e.g. localhost
    FORVALTER_MYSQL_PORT     e.g. 3306
    FORVALTER_MYSQL_USER     MySQL username
    FORVALTER_MYSQL_PASSWORD MySQL password
    FORVALTER_MYSQL_DB       Forvalter database name

  MySQL Dokument table columns (from SHOW COLUMNS):
    Id, Created, LastUpdated, KonvoluttId, OpprettetAvSoPersonId,
    Filnavn, Navn, SignertDato, SoContactId, Prosjekt, SalgId, ProsjektId, LekoId

  Filter: documenttemplatename LIKE 'Signert%' (signed documents only — matches Sesam)

  Gaps vs Sesam:
    Eier, ExternalId — not in MySQL Dokument table schema; omitted.
    Filnavn — for documents created via the Verified-for-SuperOffice signing flow,
      SuperOffice's own Document.Name is an auto-generated storage key (e.g.
      "rjbcpmzi7k_s1mqpqzsmt.pdf"), not a real filename — confirmed in Sesam's own
      historical test fixture (same exact garbled pattern). doc.header carries the
      human-entered description instead, so it's preferred here. Sesam's live Filnavn
      output for these documents is a further-cleaned variant we can't fully reproduce
      (looks like a de-duplicated prefix); this gets meaningfully closer, not byte-exact.
*/

SELECT
    {{ test_id("COALESCE(doc.documentid::VARCHAR, doc.unique_verified_id)") }}
    COALESCE(
        doc.documentid::VARCHAR || ':superoffice-document',
        doc.unique_verified_id || ':verified-document'
    )                                                   AS "Id",
    COALESCE(NULLIF(doc.header, ''), doc.name)          AS "Filnavn",
    COALESCE(doc.header, doc.name)                      AS "Navn",
    COALESCE(doc.verified_envelope_id, doc.so_envelope_id) AS "KonvoluttId",
    doc.leko_id                                         AS "LekoId",
    COALESCE(doc.created_by_person_id, u.personid, 0)      AS "OpprettetAvSoPersonId",
    CASE
        WHEN doc.project_type LIKE '%Eiendom%' THEN doc.projectname
        ELSE doc.sale_project_name
    END                                                 AS "Prosjekt",
    COALESCE(doc.signed_date, doc.createddate)          AS "SignertDato",
    doc.contactid                                       AS "SoContactId",
    CASE
        WHEN doc.project_type LIKE '%Eiendom%' THEN doc.projectid
        ELSE NULL
    END                                                 AS "ProsjektId",
    doc.saleid                                          AS "SalgId",
    doc.createddate                                     AS "Created",
    doc.updateddate                                     AS "LastUpdated"
FROM {{ ref('mrt_global_document') }} doc
LEFT JOIN {{ ref('mrt_global_user') }} u
    ON doc.owner IS NOT NULL
    AND LOWER(doc.owner) = LOWER(u.email)
WHERE doc.documenttemplatename LIKE 'Signert%'
