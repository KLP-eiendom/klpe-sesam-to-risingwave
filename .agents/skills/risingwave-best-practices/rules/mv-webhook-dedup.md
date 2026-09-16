---
title: Deduplicate Webhook Payloads Downstream in Materialized Views
impact: HIGH
impactDescription: "Prevents duplicate rows and cartesian-product row explosion in downstream marts and sinks"
tags: webhooks, deduplication, row-number, topn, _row_id
---

## Deduplicate Webhook Payloads Downstream

RisingWave webhook staging tables (`connector = 'webhook'`) are append-only logs. Since RisingWave enforces that webhook tables must contain exactly one `JSONB` column, primary keys and deduplication cannot be applied at the ingest table level. Therefore, webhooks must be deduplicated downstream in Materialized Views or Sinks.

To achieve 100% robust, idempotent deduplication:
1. **Universal _row_id ordering**: We standardise on using RisingWave's implicit system-generated `_row_id` column for ordering: `ORDER BY _row_id DESC`. This guarantees that we always process the absolute latest event that arrived in the stream, even if payload timestamps are identical, missing, or out of order.
2. **Unit Test Compatibility**: Since `_row_id` is only available on physical tables and not dbt mock unit test CTEs, you must add a Jinja conditional target check (`{% if target.name not in ('localdev', 'ci') %}`) to conditionally bypass it in unit test environments.

**Incorrect (Direct raw staging query with duplicates):**
```sql
-- Bad: direct query from staging table without deduplication, propagating duplicates downstream
WITH so AS (
    SELECT
        (payload->>'contactId')::BIGINT AS contactId,
        payload->>'name' AS name
    FROM {{ ref('stg_superoffice_contactsimple') }}
)
```

**Correct (Idempotent deduplication via _row_id and target name bypass):**
```sql
-- Good: deduplicated inside a latest CTE, choosing the latest row using _row_id
WITH latest AS (
    SELECT
        payload,
        {% if target.name not in ('localdev', 'ci') %}
        ROW_NUMBER() OVER (
            PARTITION BY (payload->>'contactId')::BIGINT
            ORDER BY _row_id DESC
        ) AS rn
        {% else %}
        1 AS rn
        {% endif %}
    FROM {{ ref('stg_superoffice_contactsimple') }}
    WHERE (payload->>'contactId') IS NOT NULL
)

SELECT
    (payload->>'contactId')::BIGINT AS contactId,
    payload->>'name' AS name
FROM latest
WHERE rn = 1
  AND NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
```

**Correct (Signere / Envelope pre-deduplication before JSONB array expansions):**
```sql
-- Good: deduplicate parent envelope rows before performing jsonb_array_elements expansions
WITH latest_envelope AS (
    SELECT
        payload,
        {% if target.name not in ('localdev', 'ci') %}
        ROW_NUMBER() OVER (
            PARTITION BY payload->>'id'
            ORDER BY _row_id DESC
        ) AS rn
        {% else %}
        1 AS rn
        {% endif %}
    FROM {{ ref('stg_verified_envelope') }}
),

latest AS (
    SELECT payload
    FROM latest_envelope
    WHERE rn = 1
)

SELECT
    doc->>'uid' AS uid,
    payload->>'id' AS envelope_id
FROM latest,
jsonb_array_elements(COALESCE(payload->'documents', '[]'::JSONB)) AS doc
```
