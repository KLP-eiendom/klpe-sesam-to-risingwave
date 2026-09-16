{{ config(
    materialized='table_with_connector',
    tags=['webhook']
) }}

-- Pusher: KdiWebHookWorker PostTicketUpdate — sends {"ticketId": <id>, "payload": {...}}.
-- Historic/seeded payloads mix TicketId/ticketId key casing; marts COALESCE both, and the
-- seeder renames TicketId->ticketId (seed_overrides.py) so the PK column always populates.
-- NOTE: ticket deletions are NOT propagated by the live flow (deleted events dead-letter in
-- KdiWebHookWorker — pre-existing gap, ported 1:1); _deleted tombstones exist only in seeded data.
CREATE TABLE {{ this }} (
  "ticketId" BIGINT,
  payload    JSONB,
  PRIMARY KEY ("ticketId")
) WITH (connector = 'webhook')
VALIDATE AS secure_compare(
  headers->>'signature',
  '{{ env_var("RW_WEBHOOK_SECRET", "") }}'
);
