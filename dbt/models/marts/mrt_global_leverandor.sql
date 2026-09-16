{{ config(
    materialized='materialized_view'
) }}

/*
  Mirrors Sesam global-leverandor.

  Sesam merged two datasets:
    d365-leverandor                      → stg_d365_leverandor
    superoffice-contactsimple-leverandor → stg_superoffice_contactsimple

  Sesam's vendor filter on SO contacts:
    custom field 15 (d365-leverandornummer) is non-zero, OR
    custom field 16 (klassifiseringkode)    != "[I:0]" AND orgnr is non-empty

  Sesam's join key: d365-leverandor.leverandor_id == d365-leverandornummer (from SO field 15)

  Implementation: D365 drives (all vendors appear); SO contact enriched where matched.

  All vendor assessment fields (leverandorgruppe, leverandorsperre, merknad,
  underavvikling, engangsleverandor) are available in stg_d365_leverandor.

  Dalux is NOT a source here and must not become one. It is a downstream consumer
  of this mart (via mrt_leverandor_dalux_writeback -> snk_leverandor_dalux), and
  letting its state back in would make the slave system an input to the definition
  of what it should itself contain. The vendor-number cross-reference it needs
  (organisationId == leverandor_id) is resolved in the sink, against
  stg_dalux_leverandor.

*/

WITH so_raw AS (
    SELECT payload
    FROM {{ ref('stg_superoffice_contactsimple') }}
    WHERE (payload->>'contactId')::BIGINT IS NOT NULL
      AND (payload->>'contactId')::BIGINT > 0
),

so AS (
    SELECT
        (payload->>'contactId')::BIGINT                             AS contactId,
        payload->>'nameDepartment'                                  AS nameDepartment,
        payload->>'orgnr'                                           AS orgnr,
        payload->>'emailAddress'                                    AS emailAddress,
        payload->>'city'                                            AS city,
        payload->>'country'                                         AS country,
        (payload->>'stop')::BOOLEAN                                 AS stop,
        NULLIF(payload->>'registeredDate', '')::TIMESTAMPTZ            AS registeredDate,
        NULLIF(payload->>'updatedDate', '')::TIMESTAMPTZ             AS updatedDate,
        -- Custom field 15: D365 leverandornummer stored as "[I:12345]"; extract digits only
        -- Guard userDefinedFields against JSON null (RisingWave throws on null::jsonb->>'key')
        NULLIF(
            REGEXP_REPLACE(
                COALESCE(
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:15',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:15',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'15',
                    ''
                ),
                '[^0-9]', '', 'g'
            ),
            ''
        )                                                           AS d365_leverandornummer,
        -- Custom field 16: vendor classification code
        COALESCE(
            NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:16',
            NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:16',
            NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'16'
        )                                                           AS klassifiseringkode,
        -- The display text sits under a COLON key (superOffice:16:DisplayText); the
        -- underscore spelling this used to look for does not exist in the payload, so
        -- klassifiseringbeskrivelse was NULL on every row. Confirmed against the captured
        -- contactsimple test data, and matches how mrt_global_leverandorvurdering has always
        -- read the same field.
        --
        -- The value is a localised string, 'NO:"Ikke godkjent";' — unwrapped with the same
        -- expression that mart uses, so both derive the field identically.
        NULLIF(
            REGEXP_REPLACE(
                COALESCE(
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:16:DisplayText',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:16:DisplayText',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'16:DisplayText',
                    ''
                ),
                '^NO:"|";$', '', 'g'
            ),
            ''
        )                                                           AS klassifiseringbeskrivelse,
        -- Normalised orgnr
        CASE
            WHEN payload->>'orgnr' IS NULL OR payload->>'orgnr' = ''
            THEN NULL
            ELSE REGEXP_REPLACE(payload->>'orgnr', '[ \-]|MVA', '', 'g')
        END                                                         AS unique_orgnr
    FROM so_raw
    WHERE NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
      -- Sesam vendor filter: field 15 non-zero OR (field 16 != [I:0] AND orgnr non-empty)
      AND (
        (
            REGEXP_REPLACE(
                COALESCE(
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:15',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:15',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'15',
                    ''
                ),
                '[^0-9]', '', 'g'
            ) != ''
            AND REGEXP_REPLACE(
                COALESCE(
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:15',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:15',
                    NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'15',
                    ''
                ),
                '[^0-9]', '', 'g'
            ) != '0'
        )
        OR (
            COALESCE(
                NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:16',
                NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:16',
                NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'16'
            ) IS NOT NULL
            AND COALESCE(
                NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'superOffice:16',
                NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'SuperOffice:16',
                NULLIF(payload->'userDefinedFields', 'null'::jsonb)->>'16'
            ) != '[I:0]'
            AND payload->>'orgnr' IS NOT NULL
            AND payload->>'orgnr' != ''
        )
      )
)

SELECT
    -- D365 vendor identity (primary key)
    dl.leverandor_id,
    dl.navn,
    dl.organisasjonsnummer,
    dl.adresse,
    -- gate_adresse is the street line on its own; dl.adresse is a multi-line
    -- composite. Needed by mrt_leverandor_dalux_writeback for Dalux's
    -- structured Address (road/zipCode/city).
    dl.gate_adresse,
    dl.postnummer,
    dl.by,
    dl.land,
    dl.kontakt_epost,
    dl.kontakt_tlf,
    dl.aktiv,
    dl.leverandorsperre,
    dl.merknad,
    dl.underavvikling,
    dl.undertvangsavviklingellertvangsopplosning,
    dl.engangsleverandor,
    dl.leverandorgruppe,

    -- SuperOffice contact linkage (NULL when no SO contact maps to this vendor)
    so.contactId,
    so.nameDepartment                           AS so_navn,
    so.orgnr                                    AS so_orgnr,
    so.unique_orgnr,
    so.emailAddress,
    so.city,
    so.country,
    so.stop,
    so.registeredDate,
    so.updatedDate,
    so.d365_leverandornummer,
    so.klassifiseringkode,
    so.klassifiseringbeskrivelse

FROM {{ ref('stg_d365_leverandor') }} dl
LEFT JOIN so
    ON dl.leverandor_id = so.d365_leverandornummer
