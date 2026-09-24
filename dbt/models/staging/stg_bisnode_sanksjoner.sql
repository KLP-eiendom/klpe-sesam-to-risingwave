{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

-- Pusher: KdiRisikoVurdering RisingWaveRepository.PostSanctionsInfoUpdate — sends the PK
-- envelope {"id": ..., "payload": {...}}. Mirrors Sesam's bisnode-sanksjoner._id: when the
-- AML screening resolved a company, id = "<verifiedCompany.dunsNo>_<verifiedCompany.regNo>";
-- otherwise (no match) id = the screening reference, so every no-match screening keeps its
-- own identity instead of collapsing into whatever company was queried.
CREATE TABLE {{ this }} (
  id      VARCHAR,
  payload JSONB,
  PRIMARY KEY (id)
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
