{{ config(
    materialized='materialized_view'
) }}

/*
  Desired state for KLP's vendors in Dalux FM — what a Dalux company SHOULD look
  like according to our masters. It holds no Dalux state at all: the cross-reference
  to Dalux's own companyId is resolved downstream in snk_leverandor_dalux, against
  stg_dalux_leverandor. Keeping actual state out of here is what stops the slave
  system from becoming an input to the definition of what it should itself contain.

  BASE: mrt_global_leverandorvurdering — the fuller vendor view, carrying Bisnode
  assessment, sanctions screening, and the two fields Dalux keeps as user-defined
  fields (lokasjon, evalueringskommentar).

  Consequence of that base, and it is deliberate: the assessment mart is driven by
  SuperOffice (FROM so, filtered on d365_leverandornummer IS NOT NULL), so a vendor
  that exists in D365 but has no SuperOffice contact does not appear and no longer
  reaches Dalux. We maintain the vendors someone has actually assessed. One already
  in Dalux without an SO contact is simply left alone — not deactivated.

  It is already one row per vendor number (ROW_NUMBER() PARTITION BY
  d365_leverandornummer ... WHERE vendor_rn = 1), so this model needs no aggregation
  of its own — it is a plain projection.

  The D365 join covers the four fields the assessment mart does not select from
  D365 (street, postcode, phone, one-off flag) plus the raw org number. A 1:1 lookup
  on the vendor number, no fan-out. D365 was never the thing that had to stay out of
  here — Dalux was.

  Matching key downstream: Dalux organisationId == D365 leverandor_id. Confirmed
  against real /companies data (companyId 10/19/56 carry organisationId
  500351/500142/503280). The Norwegian org number lives in the Dalux user-defined
  field "Org.nr." instead.

  Field ownership — what KLP writes to Dalux:
    name, address (road/zipCode/city), phoneNo, email, isActive, and all four
    user-defined fields: Klassifisering, Org.nr., Lokasjon, Vurderingskommentar.
  Dalux owns and we never write: companyTypes, disciplines, description, website.
  companyId/disciplines/companyTypes are documented as "ignored on write" anyway.

  NULL/empty desired values are NOT a delete instruction — pubsub-writer strips null
  properties before sending, so a manually maintained Dalux value survives. Hence
  NULLIF(TRIM(...), '') on everything: an empty string would blank out the Dalux
  field. This matters more than usual with this base — the assessment mart does not
  NULLIF its own SuperOffice-derived text (lokasjon is a bare REGEXP_REPLACE), so an
  empty DisplayText arrives here as '' rather than NULL.

  isactive — ANY inactivating source wins:
    D365   sperret, underavvikling, aktiv='nei', engangsleverandor='ja'
    SO     stop, or a classification the seed marks dalux_aktiv=false
    Bisnode sanksjonert
  A vendor blocked in D365 can never be active in Dalux because its classification
  says otherwise. One-off vendors are not wanted in Dalux at all; the FM API has no
  delete, so inactive is the only available way to express that. Other Bisnode
  fields (kredittrating, soliditet, betalingsanmerkning) are deliberately not acted
  on — Dalux has no field to show them in.

  Unknown classification defaults to ACTIVE (klassifisering_ukjent flags it). The
  opposite default would let a new or renamed display text in SuperOffice silently
  deactivate vendors in Dalux at the next poll.
*/

WITH v AS (
    -- SuperOffice DisplayText values are localised, and the assessment mart unwraps them
    -- with REGEXP_REPLACE(x, '^NO:"|";$', ...) — which only strips the leading NO:" and
    -- the very last ";". A single-language value comes out clean, but a multi-language one
    -- survives half-unwrapped: dev really holds 'NO:"Oslo";US:"Oslo";', which arrives here
    -- as 'Oslo";US:"Oslo'. Writing that into Dalux's Lokasjon field would be garbage, and a
    -- classification in that shape silently misses the seed lookup and counts as unknown.
    --
    -- Everything up to the first quote is the first language's text, which is the one we
    -- want, and a value that was already clean has no quote at all and passes through. The
    -- two fields treated here are the only DisplayText-derived ones; evalueringskommentar is
    -- a raw custom field (20) that may legitimately contain a quote, so it is left alone.
    SELECT
        lv.d365_leverandor_id,
        lv.navn,
        lv.city,
        lv.emailaddress,
        lv.orgnr,
        lv.evalueringskommentar,
        lv.sperret,
        lv.underavvikling,
        lv.d365_aktiv,
        lv.stop,
        lv.sanksjonert,
        NULLIF(TRIM(SPLIT_PART(COALESCE(lv.klassifiseringbeskrivelse, ''), '"', 1)), '') AS klassifisering,
        NULLIF(TRIM(SPLIT_PART(COALESCE(lv.lokasjon, ''), '"', 1)), '')                  AS lokasjon
    FROM {{ ref('mrt_global_leverandorvurdering') }} lv
)

SELECT
    v.d365_leverandor_id                                        AS organisationid,

    -- Already COALESCE(d365_navn, nameDepartment, bl_navn) in the assessment mart.
    NULLIF(TRIM(COALESCE(v.navn, '')), '')                      AS name,

    -- Dalux Address: road/number/zipCode/city. D365's `adresse` is a multi-line
    -- composite, so `gate_adresse` is the right source for road. City comes from
    -- SuperOffice — the assessment mart carries no D365 postal town. Dalux's
    -- `number` has no counterpart on our side and is left alone.
    NULLIF(TRIM(COALESCE(d.gate_adresse, '')), '')              AS address_road,
    NULLIF(TRIM(COALESCE(d.postnummer, '')), '')                AS address_zipcode,
    NULLIF(TRIM(COALESCE(v.city, '')), '')                      AS address_city,

    NULLIF(TRIM(COALESCE(d.kontakt_tlf, '')), '')               AS phoneno,
    NULLIF(TRIM(COALESCE(v.emailaddress, '')), '')              AS email,

    -- Written to the Dalux user-defined fields of the same meaning. Note the name
    -- difference on the last one: our column is evalueringskommentar (SuperOffice
    -- custom field 20), the Dalux field is called Vurderingskommentar.
    v.klassifisering,
    v.lokasjon,
    NULLIF(TRIM(COALESCE(v.evalueringskommentar, '')), '')       AS evalueringskommentar,

    -- D365 first, SuperOffice as fallback. NOT unique_orgnr: that one falls back to
    -- 'uuid-' || contactId when the org number is missing, and that string must
    -- never reach Dalux.
    COALESCE(
        NULLIF(TRIM(REGEXP_REPLACE(COALESCE(d.organisasjonsnummer, ''), '[ \-]|MVA', '', 'g')), ''),
        NULLIF(TRIM(REGEXP_REPLACE(COALESCE(v.orgnr, ''), '[ \-]|MVA', '', 'g')), '')
    )                                                            AS organisasjonsnummer,

    NOT (
        COALESCE(v.sperret, FALSE)
        OR COALESCE(v.underavvikling, FALSE)
        OR LOWER(COALESCE(v.d365_aktiv, 'ja')) = 'nei'
        OR COALESCE(v.stop, FALSE)
        OR LOWER(COALESCE(d.engangsleverandor, 'nei')) = 'ja'
        OR COALESCE(v.sanksjonert, FALSE)
        OR COALESCE(k.dalux_aktiv, TRUE) = FALSE
    )                                                            AS isactive,

    -- Visibility only: a classification SuperOffice uses but the seed doesn't know.
    -- It counts as active (see header) — this flag is how that gap stays visible.
    (
        v.klassifisering IS NOT NULL
        AND k.dalux_aktiv IS NULL
    )                                                            AS klassifisering_ukjent

FROM v
LEFT JOIN {{ ref('stg_d365_leverandor') }} d
    ON d.leverandor_id = v.d365_leverandor_id
LEFT JOIN {{ ref('dalux_klassifisering_status') }} k
    ON LOWER(v.klassifisering) = LOWER(TRIM(k.klassifiseringbeskrivelse))
-- The assessment mart keeps SuperOffice contacts whose field 15 has no D365 match,
-- keyed as 'uuid-<contactId>'; those get a NULL d365_leverandor_id from its own D365
-- join and cannot address anything in Dalux. Same filter snk_leverandorvurdering_bq
-- applies for the same reason.
WHERE v.d365_leverandor_id IS NOT NULL
  AND TRIM(v.d365_leverandor_id) != ''
