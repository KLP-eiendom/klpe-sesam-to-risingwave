# Local E2E Testing and `fast-test.sh`

This document explains the strategy and tools for running End-to-End (E2E) tests in the local RisingWave development environment.

## Overview

Local E2E testing allows you to verify the entire data pipeline—from staging models to downstream sinks—using realistic test data without needing access to production systems or external cloud services.

## The `fast-test.sh` Script

`fast-test.sh` is the primary tool for rapid local development. It automates the following steps:
1. **Dbt Seeds**: Loads static reference data.
2. **Dbt Run**: Builds the specified models (staging, marts, sinks).
3. **Test Data Loading**: Runs `scripts/load_test_data.py` to populate staging tables with JSON data.
4. **Dbt Test**: Runs data tests to verify integrity.

### Usage

Run from the `dbt/` directory:

```bash
# Test everything (staging and marts)
./fast-test.sh

# Target specific models and their downstream dependencies
./fast-test.sh --select stg_d365_contract_line+

# Force a full refresh (useful when schema changes)
./fast-test.sh --full-refresh
```

Any additional arguments are passed directly to `dbt run`.

## Test Data Convention

Test data is located in `dbt/seeds/test_data/`. The filename must match the staging table name (e.g., `stg_d365_building.json`).

### The `_id` Column
Every staging table intended for test data loading **must** define an `_id` column as its primary key.
- The `load_test_data.py` script uses this column to perform an idempotent "upsert" by deleting any existing row with that ID before inserting the new one.
- If your table uses a different name for its ID (like `id` or `Id`), you should rename it to `_id` in the `CREATE TABLE` statement.

## E2E Sink Fallbacks

To ensure that the test pipeline doesn't fail due to missing secrets (GCP project IDs) or inaccessible external databases (MySQL/JDBC), we use a **View Fallback Pattern** for all sinks.

### Implementation Pattern

In every sink model (e.g., `snk_faktura_forvalter.sql`), the materialization logic is wrapped in a target check:

```sql
{% if target.name not in ('localdev', 'ci') %}
{{ config(
    materialized='sink',
    connector='jdbc',
    ...
) }}
{% else %}
{{ config(
    materialized='view'
) }}
{% endif %}

...

{% if target.name not in ('localdev', 'ci') %}
CREATE SINK IF NOT EXISTS {{ this }}
AS
{% endif %}

SELECT ...
```

- **In `localdev`**: The model is created as a standard RisingWave VIEW. This verifies the SQL logic and column mappings without trying to connect to a real sink.
- **In `dev/test/prod`**: The model is created as a real SINK with connections to Pub/Sub or MySQL.

## Sink Deployment Strategy

### Snapshot policy (`snapshot = false`)

RisingWave sinks default to **snapshot mode** — when a sink is created, all existing
data in the upstream materialized view is replayed into the sink before live streaming begins.

| Scenario | Behaviour | Action needed |
|---|---|---|
| **Initial deployment** (new environment) | Backfill is **desired** — MySQL tables start empty | Do nothing; default is correct |
| **Re-deployment of an existing sink** (e.g. schema change) | Backfill re-sends all MV rows → MySQL processes millions of duplicate upserts | Drop the old sink, recreate with `snapshot = false` |

To re-deploy a single sink without backfill, connect to RisingWave directly and run:

```sql
-- Drop the existing sink
DROP SINK IF EXISTS public.snk_bygg_kundeportal;

-- Then redeploy via dbt with the env variable set
-- (dbt will add snapshot=false automatically — see deploy notes below)
```

> **Note:** Because all sinks use `'type': 'upsert'`, duplicate backfill rows are
> idempotent (`INSERT ... ON DUPLICATE KEY UPDATE` in MySQL), but they cause unnecessary
> load. For large MVs (Bygg, Kunder, KontraktDetaljer) re-deploying with backfill
> can take several minutes.

### Upsert Sink Performance

RisingWave sinks use upsert mode for most MySQL/JDBC destinations. This ensures that updates to the same primary key are handled correctly as overwrites.

### BACKGROUND_DDL for large-table deployments

When creating or refreshing a materialized view over a large table in production,
the DDL will block the session until the backfill completes. To avoid session
timeouts, run before the deploy:

```sql
-- Connect to RisingWave (port 4566) before running dbt
SET BACKGROUND_DDL = true;

-- Monitor progress
SELECT ddl_id, ddl_statement, progress
FROM rw_catalog.rw_ddl_progress;
```

The setting is **session-scoped** and resets when the connection closes. The
`deploy.sh` script does not set this automatically — it must be done manually
on the first deploy to a new environment or when adding MVs over large tables.

---

## Troubleshooting

### "Invalid column: _id"
If you see this error during the `Loading test data` phase, it means the staging table in RisingWave does not match the expected schema of the test loader. Ensure that:
1. The `.sql` file defines `_id VARCHAR PRIMARY KEY`.
2. You have run `./fast-test.sh` with `--full-refresh` if you just changed the column name.
