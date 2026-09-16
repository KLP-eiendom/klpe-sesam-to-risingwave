#!/usr/bin/env python3
"""
Load test data from seeds/test_data/*.json into local RisingWave staging tables.

Convention:
  stg_energinet_energyconsumption.json → INSERT INTO stg_energinet_energyconsumption

JSON format:
  {
    "entities": [{"_id": "...", "field1": "val", ...}],   # poller table
    "table_type": "webhook"                                 # optional; changes INSERT shape
  }

For webhook tables (table_type = "webhook" or detected via staging SQL):
  Each entity is inserted as: INSERT INTO stg_X (payload) VALUES (%s::jsonb)
  The entity dict becomes the payload JSON (no _id column).

For poller tables:
  Each entity must include an "_id" field.
  Values prefixed with "~f" (Sesam float notation) are stripped and inserted as float.

CDC tables (those with WHERE FALSE views in localdev) are automatically skipped.
"""

import json
import os
import sys
from pathlib import Path

import psycopg2

SCRIPT_DIR = Path(__file__).parent
DBT_DIR = SCRIPT_DIR.parent
TEST_DATA_DIR = DBT_DIR / "seeds" / "test_data"
STAGING_DIR = DBT_DIR / "models" / "staging"


def parse_value(v):
    """Strip Sesam ~f prefix and return Python value."""
    if isinstance(v, str) and v.startswith("~f"):
        return float(v[2:])
    return v


def is_cdc_table(table_name: str) -> bool:
    """Return True if the staging model uses a WHERE FALSE empty view in localdev/ci."""
    sql_path = STAGING_DIR / f"{table_name}.sql"
    if not sql_path.exists():
        return False
    return "WHERE FALSE" in sql_path.read_text(encoding="utf-8")


def is_webhook_table(table_name: str) -> bool:
    """Return True if the staging model is a webhook (connector = 'webhook') table."""
    sql_path = STAGING_DIR / f"{table_name}.sql"
    if not sql_path.exists():
        return False
    return "connector = 'webhook'" in sql_path.read_text(encoding="utf-8")


def load_webhook_rows(conn, table_name: str, entities: list):
    """Insert entities as JSONB payloads into a webhook staging table.

    Most webhook tables have only a `payload` column, but some (e.g.
    stg_superoffice_user) also declare a typed PK/extra column matching a
    top-level entity key (e.g. "personId") — extract it from the same cleaned
    entity so the column isn't left NULL (which would violate a PRIMARY KEY on
    a multi-column table and collapse every row onto one NULL-keyed upsert).
    Mirrors seed_from_sesam.py's write_webhook().
    """
    # Strip ~f prefix before serialising to JSON (unchanged from before)
    cleaned_entities = [
        {k: (float(v[2:]) if isinstance(v, str) and v.startswith("~f") else v)
         for k, v in entity.items()}
        for entity in entities
    ]

    table_cols = get_table_columns(conn, table_name)
    extra_cols = sorted(c for c in table_cols if c.lower() != "payload")

    if not extra_cols:
        # unchanged from before: single payload column, no extraction
        rows_inserted = 0
        with conn.cursor() as cur:
            for cleaned in cleaned_entities:
                cur.execute(
                    f'INSERT INTO "{table_name}" (payload) VALUES (%s::jsonb)',
                    (json.dumps(cleaned),),
                )
                rows_inserted += 1
        conn.commit()
        return rows_inserted

    # Validate BEFORE inserting: an entity missing a value for an extra column would
    # otherwise flow through as NULL, silently collapsing every row onto the same
    # NULL-keyed upsert (or failing a NOT NULL/PK constraint later, after some rows
    # already committed). Fail fast instead, naming the table/column(s)/samples.
    bad = []
    bad_cols = set()
    for cleaned in cleaned_entities:
        missing = [c for c in extra_cols if cleaned.get(c) is None]
        if missing:
            bad.append(cleaned)
            bad_cols.update(missing)
    if bad:
        cols = ", ".join(sorted(bad_cols))
        samples = [
            str(entity["_id"]) if entity.get("_id") is not None else repr(entity)[:150]
            for entity in bad[:3]
        ]
        raise ValueError(
            f"[{table_name}] ERROR: {len(bad)} entit{'y' if len(bad) == 1 else 'ies'} missing "
            f"required column(s) [{cols}] (entity.get() returned None) — would insert NULL into "
            f"a NOT NULL/PK column. Aborting before INSERT — table left untouched. "
            f"Sample entities: {samples}"
        )

    col_list = ", ".join(['"payload"'] + [f'"{c}"' for c in extra_cols])
    placeholders = ", ".join(["%s::jsonb"] + ["%s"] * len(extra_cols))
    insert_sql = f'INSERT INTO "{table_name}" ({col_list}) VALUES ({placeholders})'

    rows_inserted = 0
    with conn.cursor() as cur:
        for cleaned in cleaned_entities:
            row = [json.dumps(cleaned)] + [cleaned.get(c) for c in extra_cols]
            cur.execute(insert_sql, row)
            rows_inserted += 1
    conn.commit()
    return rows_inserted


def get_table_columns(conn, table_name: str) -> set[str]:
    """Return the set of column names that exist in the table (from information_schema)."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = %s",
            (table_name,),
        )
        return {row[0] for row in cur.fetchall()}


def load_poller_rows(conn, table_name: str, entities: list):
    """Insert entities into a poller staging table (requires _id in each entity)."""
    if not entities:
        return 0

    # Collect all column names across all rows, then filter to table's actual columns
    all_json_cols = list(dict.fromkeys(k for e in entities for k in e.keys()))
    table_cols = get_table_columns(conn, table_name)

    if not table_cols:
        print(f"  [{table_name}] ERROR: table has no columns (does it exist?) — skipping", file=sys.stderr)
        return 0

    # Build a case-insensitive lookup: lowercase → original DB column name.
    # information_schema preserves the case of quoted identifiers (e.g. "byggNavnId",
    # "GnrBnr"), so a naive lowercase set comparison misses those columns.
    table_cols_lower = {col.lower(): col for col in table_cols}

    # Match JSON keys (case-insensitive) to DB columns; store original DB name
    # so the INSERT can use the correctly-cased quoted column name.
    db_to_json_map = {}  # original_db_col → original_json_key
    for json_key in all_json_cols:
        l_key = json_key.lower()
        if l_key in table_cols_lower:
            db_to_json_map[table_cols_lower[l_key]] = json_key

    all_db_cols = list(db_to_json_map.keys())
    skipped = [c for c in all_json_cols if c.lower() not in table_cols_lower]

    if skipped:
        print(f"  [{table_name}] WARNING: ignoring JSON fields not in table: {skipped}")

    if "_id" not in [c.lower() for c in all_db_cols]:
        print(f"  [{table_name}] ERROR: database table missing '_id' column — skipping", file=sys.stderr)
        return 0

    col_list = ", ".join([f'"{c}"' for c in all_db_cols])
    placeholders = ", ".join(["%s"] * len(all_db_cols))
    delete_sql = f'DELETE FROM "{table_name}" WHERE "_id" = %s'
    insert_sql = f'INSERT INTO "{table_name}" ({col_list}) VALUES ({placeholders})'

    rows_inserted = 0
    with conn.cursor() as cur:
        for entity in entities:
            # 1. DELETE existing row with same _id (if any)
            cur.execute(delete_sql, (entity.get("_id"),))
            # 2. INSERT new row
            row = [parse_value(entity.get(db_to_json_map[c])) for c in all_db_cols]
            cur.execute(insert_sql, row)
            rows_inserted += 1
    conn.commit()
    return rows_inserted


def load_file(conn, json_path: Path):
    table_name = json_path.stem  # e.g. stg_energinet_energyconsumption

    if is_cdc_table(table_name):
        print(f"  [{table_name}] CDC/view table — skipped")
        return

    data = json.loads(json_path.read_text(encoding="utf-8"))
    entities = data.get("entities", [])
    if not entities:
        print(f"  [{table_name}] No entities — skipping")
        return

    explicit_webhook = data.get("table_type") == "webhook"
    webhook = explicit_webhook or is_webhook_table(table_name)

    with conn.cursor() as cur:
        # Clear existing data before loading test set
        # Using DELETE FROM instead of TRUNCATE for RisingWave compatibility
        cur.execute(f'DELETE FROM "{table_name}"')
    conn.commit()

    if webhook:
        n = load_webhook_rows(conn, table_name, entities)
    else:
        n = load_poller_rows(conn, table_name, entities)

    print(f"  [{table_name}] {'webhook' if webhook else 'poller'}: inserted/updated {n} rows")


def main():
    host = os.environ.get("DBT_RW_HOST", "localhost").strip()
    port = int(os.environ.get("DBT_RW_PORT", "4566").strip())
    user = os.environ.get("DBT_RW_USER", "root").strip()
    password = os.environ.get("DBT_RW_PASSWORD", "").strip()
    dbname = os.environ.get("DBT_RW_DBNAME", "dev").strip()

    json_files = sorted(TEST_DATA_DIR.glob("stg_*.json"))
    if not json_files:
        print(f"No test data files found in {TEST_DATA_DIR}", file=sys.stderr)
        sys.exit(1)

    print(f"Connecting to RisingWave at {host}:{port} db={dbname}")
    conn = psycopg2.connect(host=host, port=port, user=user, password=password, dbname=dbname)
    try:
        for path in json_files:
            print(f"Loading {path.name}...")
            load_file(conn, path)
    finally:
        conn.close()

    print("Done loading test data.")


if __name__ == "__main__":
    main()
