{% if target.name not in ('localdev', 'ci') %}
{{ config(materialized='sink', tags=['sink']) }}
{% else %}
{{ config(materialized='view') }}
{% endif %}

/*
  Google Pub/Sub sink for the vendor write-back to Dalux FM.

  pubsub-writer consumes the topic and PATCHes the Dalux Field Management API:
    PATCH {dalux-base-url}/2.1/companies/{companyId}

  This is the UPDATE branch only. The INNER JOIN to stg_dalux_leverandor is what
  makes it so: a vendor with no Dalux company simply doesn't emit. Creation
  (POST /2.1/companies) is deliberately not wired up — the FM API has no
  idempotency key on create, and the create scope hasn't been agreed against real
  data. See docs/dalux_leverandor_writeback.md.

  Why the join lives here and not in a mart: it is used by exactly one sink, and
  the project's guidance is that sinks may JOIN directly, with a dedicated
  intermediate mart only when the same join is shared. Keeping it here is also
  what lets mrt_leverandor_dalux_writeback stay pure desired state, with no idea
  what Dalux currently holds.

  FLAT COLUMNS ON PURPOSE. Dalux wants a nested body — {"data": {..., "address":
  {...}, "userDefinedFields": {"items": [...]}}} — but this sink emits only flat
  scalars, and pubsub-writer assembles the nested shape. Two reasons:
    1. Whether RisingWave's `FORMAT PLAIN ENCODE JSON` serialises a JSONB column
       as nested JSON or as an escaped string is not verified, and no model in
       this project builds nested JSON today.
    2. The "empty means no opinion" rule can't be expressed by a sink anyway — a
       null column serialises as `"email": null`, which would blank out whatever a
       Dalux user maintains. pubsub-writer strips null properties before sending,
       so the assembly has to happen there regardless.
  So the columns below are a transport format for the writer, not Dalux's schema.

  Column roles for the writer:
    companyId                     -> the {companyId} in the URL, removed from the body
    name/phoneNo/email/isActive   -> passed through into `data` as-is
    address_*                     -> assembled into the nested `address` object
    klassifisering                -> value of the Dalux UDF "Klassifisering"
    organisasjonsnummer           -> value of the Dalux UDF "Org.nr."
    lokasjon                      -> value of the Dalux UDF "Lokasjon"
    evalueringskommentar          -> value of the Dalux UDF "Vurderingskommentar"
                                     (the names differ: ours is SuperOffice custom
                                     field 20, Dalux calls the field Vurderingskommentar)
    userDefinedFields             -> Dalux's CURRENT UDF array, echoed back with only
                                     the four values above replaced, so anything else
                                     in it survives
*/

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}
WITH dalux_unique AS (
    -- One Dalux company per vendor number, or none. An organisationId held by two
    -- companies would otherwise fan out into two PATCHes against arbitrary
    -- duplicates. It is unique in practice (soft constraint in Dalux, and the key
    -- of the mart on our side), so this drops nothing in normal operation.
    SELECT organisationid
    FROM {{ ref('stg_dalux_leverandor') }}
    WHERE organisationid IS NOT NULL
      AND TRIM(organisationid) != ''
    GROUP BY organisationid
    HAVING COUNT(*) = 1
)

SELECT
        {{ test_id('d.companyid') }}
    d.companyid                     AS "companyId",
    w.name                          AS "name",
    w.phoneno                       AS "phoneNo",
    w.email                         AS "email",
    w.isactive                      AS "isActive",
    w.address_road                  AS "address_road",
    w.address_zipcode               AS "address_zipcode",
    w.address_city                  AS "address_city",
    w.klassifisering                AS "klassifisering",
    w.organisasjonsnummer           AS "organisasjonsnummer",
    w.lokasjon                      AS "lokasjon",
    w.evalueringskommentar          AS "evalueringskommentar",
    d.userdefinedfields             AS "userDefinedFields"
FROM {{ ref('mrt_leverandor_dalux_writeback') }} w
JOIN dalux_unique u
    ON u.organisationid = w.organisationid
JOIN {{ ref('stg_dalux_leverandor') }} d
    ON d.organisationid = w.organisationid
{% if target.name not in ('localdev', 'ci') %}
WITH (
    connector = 'google_pubsub',
    pubsub.project_id = '{{ env_var("GCP_PROJECT_ID", "example-project-dev") }}',
    pubsub.topic = '{{ env_var("GCP_PUBSUB_TOPIC_LEVERANDOR_DALUX", "leverandor-dalux-" ~ target.name) }}',
    pubsub.endpoint = 'pubsub.googleapis.com',
    pubsub.credentials = SECRET risingwave_gcp_sa,
    pubsub.primary_key = 'companyId',
    -- Ordering guarantee, not a duplicate of primary_key: the writer PATCHes the same
    -- company repeatedly, so without a per-company message key Pub/Sub may deliver two
    -- updates out of order and an older state wins. Same property as snk_bygg_findable.
    pubsub.message_key = 'companyId'
)
FORMAT PLAIN ENCODE JSON (force_append_only = 'true');
{% endif %}
