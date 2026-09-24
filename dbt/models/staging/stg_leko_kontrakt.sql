{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

-- No RW pusher exists yet for this table (seed-fed; the Leko contract push is not
-- built/active). Any future pusher must send the PK envelope {"id": "...", "payload": {...}}.
CREATE TABLE {{ this }} (
  id      VARCHAR,
  payload JSONB,
  PRIMARY KEY (id)
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
