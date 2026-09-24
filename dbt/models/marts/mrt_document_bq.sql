{{ config(
    materialized='materialized_view'
) }}

/*
  Document data enriched with customer info for BigQuery sink.
  Mirrors Sesam dokument-bq (jsoncontent hop + content rule).
  Used by snk_document_bq.

  Filter applied here: documenttemplatename LIKE 'Signert%' AND name LIKE '%.pdf'
  (matches Sesam pipe filter — signed PDF documents only).

  Gap vs Sesam:
    opprettetAv vs kontaktperson — Sesam distinguished createdBy.fullName from associate.fullName;
            mrt_global_document exposes only associate.fullName (created_by_name) for both.
*/

SELECT
    d.documentId,
    COALESCE(d.name, d.header)           AS filnavn,
    d.externalRef,
    d.createdDate,
    d.created_by_name,
    d.created_by_full_name,
    d.projectName,
    d.leko_document_uid,
    d.leko_envelope_uid,
    d.contactId,
    c.kundenummer                         AS c_kundenummer,
    c.nameDepartment                      AS c_namedepartment
FROM {{ ref('mrt_global_document') }} d
LEFT JOIN {{ ref('mrt_global_customer') }} c
    ON d.contactId = c.contactId
WHERE d.documentTemplateName LIKE 'Signert%'
  AND LOWER(d.name) LIKE '%.pdf'
