{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

CREATE TABLE {{ this }} (
  "projectId" BIGINT,
  payload     JSONB,
  PRIMARY KEY ("projectId")
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
