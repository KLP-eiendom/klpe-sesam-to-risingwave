{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    tags=['sink']
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

/*
  Pub/Sub sink for service contract data destined for KLP Findable (Firestore `serviceavtaler` collection).
  Format is JSON, and the KlpeFindable API acts as the worker consuming this topic via a push subscription.

  Expected fields in Findable:
  - id: string            — CONCAT(buildingId, '_', serviceId)
  - buildingId: string
  - serviceId: number
  - name: string
  - firma: string
  - type: string
  - ansvarlig: string
  - startdato: timestamp
  - utlopsdato: timestamp
  - oppsigelsesfrist: string
  - varighet: string
  - fornyelse: string
  - prisregulering: string
  - omfang: string
  - annet: string
  - bygningsdel: string
  - oppfolgingsdato: timestamp
  - garantidato: timestamp
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
SELECT
        {{ test_id("CONCAT(byggid, '_', id::VARCHAR)") }}
CONCAT(byggid, '_', id::VARCHAR)            AS "id",
    byggid                                       AS "buildingId",
    id::DECIMAL                                  AS "serviceId",
    navn                                         AS "name",
    firma                                        AS "firma",
    type                                         AS "type",
    ansvarlig                                    AS "ansvarlig",
    startdato AT TIME ZONE 'UTC'                 AS "startdato",
    utlopsdato AT TIME ZONE 'UTC'                AS "utlopsdato",
    oppsigelsesfrist                             AS "oppsigelsesfrist",
    varighet                                     AS "varighet",
    fornyelse                                    AS "fornyelse",
    prisregulering                               AS "prisregulering",
    omfang                                       AS "omfang",
    annet                                        AS "annet",
    bygningsdel                                  AS "bygningsdel",
    oppfolgingsdato AT TIME ZONE 'UTC'           AS "oppfolgingsdato",
    garantidato AT TIME ZONE 'UTC'               AS "garantidato"
FROM {{ ref('stg_fdvweb_serviceavtale') }}
WHERE byggid IS NOT NULL
  AND id IS NOT NULL
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = 'klpe-findable-serviceavtale-sync',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'id'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
