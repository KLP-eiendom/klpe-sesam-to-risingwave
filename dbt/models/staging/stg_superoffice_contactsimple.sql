{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

CREATE TABLE {{ this }} (
  "contactId" BIGINT,
  payload     JSONB,
  PRIMARY KEY ("contactId")
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
