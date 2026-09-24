{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

-- Pusher: KdiLekoWorker RisingWaveRepository — sends {"soDokumentId": "...", "payload": {...}}
-- (camelCase-serialized) to match this PK column and the camelCase payload keys read downstream.
CREATE TABLE {{ this }} (
  "soDokumentId" VARCHAR,
  payload        JSONB,
  PRIMARY KEY ("soDokumentId")
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
