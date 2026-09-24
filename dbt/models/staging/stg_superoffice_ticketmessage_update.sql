{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

CREATE TABLE {{ this }} (
  "ticketMessageId" BIGINT,
  payload           JSONB,
  PRIMARY KEY ("ticketMessageId")
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
