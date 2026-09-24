# Sesam Seeding Guide

This guide explains how to populate RisingWave staging (`stg_*`) tables from Sesam source datasets using the `seed_from_sesam.py` script.

---

## Why Seeding is Necessary

For webhook-fed staging tables (like `stg_superoffice_user`) or environments that are newly deployed or restored, the staging tables are initially empty. Because RisingWave's pollers and live streams may not automatically backfill all historical records, we must manually "seed" these staging tables from Sesam's historical source datasets.

Without seeding:
1. Downstream marts and materialized views will be empty or have incomplete data.
2. Downstream `upsert` sinks will compute that the missing records have been "deleted". The sink will then propagate these deletions downstream to target databases (like MySQL/BigQuery).
3. If target databases have foreign key constraints (e.g., `ON DELETE RESTRICT` on dependent tables like `BrukerTilgang`), these false deletes will cause the sink to crash with a `SINK_FAIL` foreign key violation.

---

## How Seeding Works

The seeding script, [seed_from_sesam.py](dbt/scripts/seed_from_sesam.py), works by:
1. **Reading** from a Sesam source dataset (fetched via the Sesam Node API with credentials retrieved from HashiCorp Vault `kdi/<env>`).
2. **Transforming** the entities:
   - Stripping Sesam transit prefixes (e.g., `~f`, `~t`).
   - Recursively removing namespace prefixes (e.g., `superoffice-user:`) from fields and nested arrays/objects.
   - Applying field renames and custom primary key (`_id`) mapping expressions.
3. **Writing** directly to the RisingWave staging table (`DELETE FROM stg_...` followed by bulk `INSERT` using `psycopg2` and credentials from Vault `risingwave/<env>`).
4. **Triggering Streaming**: RisingWave then automatically propagates the inserted staging records downstream to marts, materialized views, and sinks.

---

## Configuration Files

The seeding behavior is driven by two main configuration files:

### 1. `seed_targets.json`
Located at [seed_targets.json](dbt/scripts/seed_targets.json), this registry tracks which staging tables are already seeded or have data:
- `true`: Already has data. The script will **prompt you** before re-seeding to prevent accidental clobbering.
- `false`: Empty or unseeded. The script will seed it immediately.

You can initialize/refresh this file from the live database counts by running:
```bash
python scripts/seed_from_sesam.py --init-config --rw-env <env>
```

### 2. `seed_overrides.py`
Located at [seed_overrides.py](dbt/scripts/seed_overrides.py), this contains per-table overrides for:
- `sesam_dataset`: Custom source dataset (e.g., seeding `stg_superoffice_user` from `superoffice-migrateduser` instead of `superoffice-user` to filter down to the 6,701 canonical users).
- `id`: Custom `IdExpression` to compute the staging `_id`.
- `field_renames`: Dict mapping Sesam field names to staging columns.
- `where_filter`: Callable filter to keep only rows matching specific conditions.

---

## Usage Guide

All commands must be executed from the `dbt/` directory.

### Environment Safety Guards
The script enforces strict rules to prevent production data corruption:
- `--rw-env prod` requires `--sesam-env prod` and the `--confirm-prod` flag.
- Reading from `prod` and writing to `dev` or `test` is **allowed** (e.g., `--sesam-env prod --rw-env test`) since the target databases contain no sensitive user credentials.

### Common Commands

#### 1. Dry Run (Recommended First Step)
Simulate fetching and transforming without writing to the database:
```bash
python scripts/seed_from_sesam.py --sesam-env test --rw-env dev --select stg_superoffice_user --dry-run
```

#### 2. Seed a Specific Table
Populate a specific staging table in dev:
```bash
python scripts/seed_from_sesam.py --sesam-env test --rw-env dev --select stg_superoffice_user
```

#### 3. Seed All Unpopulated Tables
Automatically seed all tables marked `false` in `seed_targets.json`:
```bash
python scripts/seed_from_sesam.py --sesam-env test --rw-env dev --all
```

#### 4. Refresh Seeding Progress Configuration
Sync `seed_targets.json` with the current row counts in RisingWave:
```bash
python scripts/seed_from_sesam.py --init-config --rw-env dev
```

---

## Critical Troubleshooting: Sink Fails with Foreign Key Violation

### Case Study: `snk_user_kundeportal` Sink Failure
If you see an error log like this in the GCP cloud console or sink status:
```json
{
  "sinkFail": {
    "connector": "jdbc",
    "error": "Remote sink error: INTERNAL: Error when exec 23000, message Cannot delete or update a parent row: a foreign key constraint fails (`kundeportal-db-dev`.`BrukerTilgang`, CONSTRAINT `FK_BrukerTilgang_Bruker_BrukerId` FOREIGN KEY (`BrukerId`) REFERENCES `Bruker` (`BrukerId`) ON DELETE RESTRICT ON UPDATE RESTRICT)",
    "sinkName": "snk_user_kundeportal"
  }
}
```

### Diagnosis
1. Check the row count of the staging table (`stg_superoffice_user`) in the target environment (e.g., `dev`).
2. If the count is very low (e.g. 117 records instead of the canonical 6,701 records), RisingWave thinks that the other ~6,584 users have been deleted.
3. As a result, the upsert sink attempts to propagate these deletions to the downstream MySQL database (`Bruker` table).
4. Because some of those users still have dependent rows in `BrukerTilgang`, the database blocks the deletion, causing the sink to fail.

### Resolution Steps
1. **Seed the Staging Table**: Populate the staging table with the full, canonical dataset from Sesam:
   ```bash
   python scripts/seed_from_sesam.py --sesam-env test --rw-env dev --select stg_superoffice_user
   ```
2. **Clean Up Orphaned Records**: If there are stale test records in the downstream database (e.g., in `BrukerTilgang`) that prevent updates or deletions, clean them up manually using a SQL script or utility.
3. **Resume Sink**: RisingWave will automatically retry and resume processing once the parent rows are restored, and counts in the sink will align correctly.
