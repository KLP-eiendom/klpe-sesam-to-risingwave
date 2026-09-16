{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

-- Pusher: KdiVerifiedApi RisingWaveRepository.PostEnvelopeUpdate — sends the PK envelope
-- {"id": "...", "payload": {...}}. `id` is the Verified envelope id (top-level lowercase
-- in the raw Verified API JSON).
CREATE TABLE {{ this }} (
  id      VARCHAR,
  payload JSONB,
  PRIMARY KEY (id)
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
