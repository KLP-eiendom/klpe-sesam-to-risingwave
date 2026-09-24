{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

-- Pusher: KdiRisikoVurdering RisingWaveRepository.PostForetakInfoUpdate — sends the PK
-- envelope {"id": "<dunsNumber>_<registrationNumber-or-vatNumber>", "payload": {...}}.
-- Mirrors Sesam's own dataset identity (bisnode-leverandor._id): dunsNumber is the primary
-- disambiguator, since registrationNumber/vatNumber (Bisnode Global API) are free-text and
-- not always numeric or present. id is nested under companyInformation.identifiers, so RW's
-- top-level-only webhook decode can't extract it from the payload itself — computed by the
-- pusher. The legacy Norwegian SOAP path (HentForetakResponse) has no DUNS number, so its
-- rows key on the plain orgnr string instead.
CREATE TABLE {{ this }} (
  id      VARCHAR,
  payload JSONB,
  PRIMARY KEY (id)
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
