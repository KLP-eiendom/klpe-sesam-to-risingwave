# Curated Showcase Tour: Sesam to RisingWave in 5 Key Flows

Welcome to the **KLP Eiendom Sesam-to-RisingWave Showcase Tour**! 

This repository contains an enterprise data platform featuring ~140 models, 10 poller services, and streaming CDC. To help other Sesam customers understand the architecture without getting overwhelmed by domain-specific details, this tour walks through the **5 most important integration patterns** implemented in the codebase.

---

## Tour Map

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             5 CORE SHOWCASE FLOWS                                │
├──────────────────────────────────────────────────────────────────────────────────┤
│ 1. CRM REST Poller ──────► Global Customer Mart ──────► MySQL JDBC Sink          │
│    (REST API)              (Outer Join & Merge)         (Upsert with PK)         │
│                                                                                  │
│ 2. Webhook Ingestion ────► Deduplication & Tombstone ─► Downstream Ticket Sink   │
│    (Append-only JSONB)     (Windowed ROW_NUMBER)        (Filtered Stream)        │
│                                                                                  │
│ 3. Transactional CDC ────► Real-Time Workflow Mart ───► Event / App Sink         │
│    (Postgres WAL Stream)   (Sub-second Latency)         (Continuous Push)        │
│                                                                                  │
│ 4. Cross-System Merger ──► Global Employee Mart ──────► BigQuery Lake Sink       │
│    (Multi-Source Ingest)   (Identity Resolution)        (Data Lake Export)       │
│                                                                                  │
│ 5. Parity Test Suite ────► Sesam vs RisingWave ───────► Parity Diff Report       │
│    (Automated Validation)  (Row-by-row Verification)    (Zero Data Loss)         │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Flow 1: CRM REST API Ingestion → Entity Resolution → JDBC Sink

This flow demonstrates how to replace a scheduled Sesam REST pipe with a streaming poller, merge it with ERP data in SQL, and stream the result to a relational database.

### 1. Ingestion via Poller
- **Code:** [`src/cloud-run/superoffice-entity-poller/`](src/cloud-run/superoffice-entity-poller/)
- **Staging DDL:** [`dbt/models/staging/stg_superoffice_contact.sql`](dbt/models/staging/stg_superoffice_contact.sql)
- **Pattern:** Since SaaS REST APIs don't emit database change streams, a lightweight .NET worker polls paginated endpoints, calculates primary keys via `IdExpressionEvaluator`, and batch-upserts into RisingWave via Npgsql.

### 2. Stream Merge & Hop in SQL
- **Model:** [`dbt/models/marts/mrt_global_customer.sql`](dbt/models/marts/mrt_global_customer.sql)
- **Sesam Counterpart:** Previously handled in Sesam using DTL `hops` between `customer` and `crm-contact` with a `strategy: compact` merge.
- **RisingWave SQL:**
  ```sql
  SELECT
      COALESCE(so.contactId, d365.kundenummer) AS customer_id,
      d365.navn                               AS customer_name,
      so.emailAddress                         AS email,
      so.contactPhoneFormattedNumber          AS phone
  FROM {{ ref('stg_d365_kunde') }} d365
  FULL OUTER JOIN {{ ref('stg_superoffice_contact') }} so
      ON d365.kundenummer = so.number
  ```
  *RisingWave maintains this `FULL OUTER JOIN` continuously in memory. When a customer is edited in either D365 or SuperOffice, the output updates instantly.*

### 3. Outbound JDBC Sink
- **Sink:** [`dbt/models/sinks/snk_customer_forvalter.sql`](dbt/models/sinks/snk_customer_forvalter.sql)
- **Configuration:**
  ```sql
  {{ config(
      materialized='sink',
      connector='jdbc',
      connector_parameters={
          'jdbc.url': 'jdbc:mysql://' ~ env_var('FORVALTER_MYSQL_HOST', 'localhost') ~ ':3306/target_db',
          'table.name': 'Kunde',
          'type': 'upsert',
          'primary_key': 'Id'
      }
  ) }}
  ```
  *Streams updates continuously to the target MySQL table using upsert semantics.*

---

## Flow 2: Append-Only Webhooks → Deduplication CTE → Tombstone Deletions

This flow addresses a common challenge in event-driven architectures: SaaS webhooks that arrive as an append-only stream of JSON events, including duplicate deliveries and deleted records.

### 1. Ingestion: Raw JSONB Webhooks
- **Staging DDL:** [`dbt/models/staging/stg_superoffice_ticket.sql`](dbt/models/staging/stg_superoffice_ticket.sql)
- **Pattern:** Webhooks are ingested into a table with a single `payload JSONB` column:
  ```sql
  CREATE TABLE stg_superoffice_ticket (
      id VARCHAR,
      payload JSONB
  ) WITH (connector = 'webhook');
  ```

### 2. State Reconstruction with Window Functions
- **Model:** [`dbt/models/marts/mrt_superoffice_ticket.sql`](dbt/models/marts/mrt_superoffice_ticket.sql)
- **Sesam Counterpart:** Sesam's built-in dataset compaction and `create-tombstone` DTL function.
- **RisingWave SQL Pattern:**
  ```sql
  WITH ranked_events AS (
      SELECT
          payload->>'id'                         AS ticket_id,
          payload->>'title'                      AS title,
          payload->>'status'                     AS status,
          (payload->>'_deleted')::BOOLEAN        AS is_deleted,
          (payload->>'updated_at')::TIMESTAMPTZ  AS updated_at,
          ROW_NUMBER() OVER (
              PARTITION BY payload->>'id'
              ORDER BY (payload->>'updated_at')::TIMESTAMPTZ DESC
          ) AS rn
      FROM {{ ref('stg_superoffice_ticket') }}
  )
  SELECT ticket_id, title, status
  FROM ranked_events
  WHERE rn = 1 
    AND (is_deleted IS FALSE OR is_deleted IS NULL);
  ```
  *RisingWave optimizes windowed `ROW_NUMBER() = 1` queries into incremental state tables, ensuring negligible memory overhead even with millions of webhook events.*

### 3. Outbound Sink
- **Sink:** [`dbt/models/sinks/snk_ticket_kundeportal.sql`](dbt/models/sinks/snk_ticket_kundeportal.sql)

---

## Flow 3: Zero-Latency Database CDC (Change Data Capture)

This flow shows how to stream database changes directly from transactional databases into analytical views without any polling overhead.

### 1. Native PostgreSQL / MySQL CDC Source
- **Source DDL:** [`dbt/models/sources/src_camunda_cdc.sql`](dbt/models/sources/src_camunda_cdc.sql)
- **Configuration:**
  ```sql
  CREATE SOURCE src_camunda_cdc WITH (
      connector = 'postgres-cdc',
      hostname = 'postgres-host',
      port = '5432',
      username = 'cdc_user',
      password = '...',
      database.name = 'process_engine',
      schema.name = 'public'
  );
  ```
  *RisingWave connects directly to the PostgreSQL Write-Ahead Log (WAL) or MySQL binlog. No Debezium or Kafka cluster required.*

### 2. Staging and Real-Time State
- **Staging:** [`dbt/models/staging/stg_camunda_act_hi_procinst.sql`](dbt/models/staging/stg_camunda_act_hi_procinst.sql)
- **Sink:** [`dbt/models/sinks/snk_processinstance_powerapp.sql`](dbt/models/sinks/snk_processinstance_powerapp.sql)

---

## Flow 4: Cross-System Identity Resolution & Merger

In enterprise hubs, different systems often identify the same entity with different keys (e.g. employee IDs, email addresses, or Active Directory UPNs).

### 1. Multi-System Ingestion
- **Inputs:**
  - `stg_d365_ansatt` (ERP employee registry)
  - `stg_superoffice_user` (CRM user accounts)
  - `stg_superoffice_csuser` (CRM customer service accounts)

### 2. Identity Resolution Mart
- **Model:** [`dbt/models/marts/mrt_global_internaluser.sql`](dbt/models/marts/mrt_global_internaluser.sql)
- **Pattern:** Resolves matching users across systems using normalized email expressions, handling active vs retired flags and deduplication:
  ```sql
  -- Normalized email matching with priority fallback:
  COALESCE(LOWER(d365.epost), LOWER(so.email)) AS normalized_email
  ```
- **Unit Test:** [`dbt/models/marts/unit_tests/mrt_global_internaluser.yml`](dbt/models/marts/unit_tests/mrt_global_internaluser.yml) (demonstrates pure SQL unit testing in dbt without a live cluster).

---

## Flow 5: The Migration Safety Net (Parity Verification Suite)

How do you prove that your new RisingWave pipeline produces the exact same output as your existing Sesam pipes before switching traffic?

### 1. Seeding RisingWave Directly from Sesam (`seed_from_sesam.py`)
- **Script:** [`dbt/scripts/seed_from_sesam.py`](dbt/scripts/seed_from_sesam.py)
- **What it does:** Reads source datasets from an active Sesam instance and loads them directly into RisingWave staging tables. This lets you test all downstream marts and sinks against real data without waiting for live pollers.
  ```bash
  python dbt/scripts/seed_from_sesam.py --sesam-env test --rw-env test --select stg_superoffice_contact
  ```

### 2. Deep Value Verification (`verify_sink_values.py`)
- **Script:** [`dbt/scripts/verify_sink_values.py`](dbt/scripts/verify_sink_values.py)
- **What it does:** Fetches output rows from Sesam and RisingWave sinks, normalizes timestamps and casing, and flags any field differences:
  ```bash
  python dbt/scripts/verify_sink_values.py --env test --sink snk_customer_forvalter
  ```

### 3. Volume and Count Sanity (`verify_sink_counts.py`)
- **Script:** [`dbt/scripts/verify_sink_counts.py`](dbt/scripts/verify_sink_counts.py)
- **What it does:** Verifies that row counts match across dozens of sinks in seconds.

---

## Running the Showcase Locally

To test these flows on your own machine in 5 minutes:

```bash
# 1. Start RisingWave + MySQL + Postgres via Docker
docker compose up -d

# 2. Configure environment
cp .env.example .env.development

# 3. Install Python dependencies
pip install -r requirements.txt

# 4. Run seeds, models, and unit tests
cd dbt
dbt seed --target localdev
dbt run --target localdev --select tag:showcase
dbt test --target localdev
```

---

## Exploring Beyond the Showcase

While this tour highlighted the 5 fundamental patterns, the repository includes dozens of additional real-world models in [`dbt/models/`](dbt/models/) covering:
- Complex temporal filtering and date arithmetic
- Multi-language string unwrapping
- Cloud PubSub and Google BigQuery connectors
- Automated CI/CD deployment workflows with change detection
