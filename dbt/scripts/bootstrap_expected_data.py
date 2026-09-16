#!/usr/bin/env python3
"""
Bootstrap expected_data JSON files by querying mart output from a live RisingWave instance.

Run this AFTER:
  1. dbt run (staging + marts deployed)
  2. load_test_data.py (test data loaded into staging tables)
  3. sleep 3 (MVs have had time to refresh)

For each models/sinks/snk_*.sql that references a mart via {{ ref('mrt_...') }} or
{{ ref('stg_...') }}, this script:
  1. Queries SELECT * FROM <mart>
  2. Writes the result as JSON to expected_data/snk_<name>.json
  3. Writes a companion expected_data/snk_<name>.test.json with mart name and blacklist

This establishes a baseline. Run once to generate, then commit the expected_data files.
Subsequent runs of verify_e2e.py will detect regressions.

Usage:
  python3 scripts/bootstrap_expected_data.py
  python3 scripts/bootstrap_expected_data.py --overwrite   # overwrite existing files
  python3 scripts/bootstrap_expected_data.py --dry-run     # print only, no writes

Columns always blacklisted (non-deterministic): created, lastupdated, _rw_timestamp
"""

import json
import os
import re
import sys
from decimal import Decimal
from pathlib import Path

import psycopg2
import psycopg2.extras

SCRIPT_DIR = Path(__file__).parent
DBT_DIR = SCRIPT_DIR.parent
SINKS_DIR = DBT_DIR / "models" / "sinks"
EXPECTED_DIR = DBT_DIR / "models" / "sinks" / "unit_tests" / "expected_data"

ALWAYS_BLACKLIST = {"created", "lastupdated", "_rw_timestamp"}


def extract_mart_ref(sink_sql: str) -> str | None:
    """Extract the first ref('...') from a sink SQL file."""
    m = re.search(r"ref\('([^']+)'\)", sink_sql)
    return m.group(1) if m else None


def serialise(obj):
    """JSON-serialise psycopg2 row values."""
    if obj is None:
        return None
    if isinstance(obj, Decimal):
        f = float(obj)
        return f if f == int(f) else f
    if isinstance(obj, (int, float, str, bool)):
        return obj
    return str(obj)


def query_mart(conn, mart_name: str) -> tuple[list[str], list[dict]]:
    """Return (column_names, rows) from a mart query."""
    with conn.cursor() as cur:
        cur.execute(f'SELECT * FROM "{mart_name}"')
        cols = [desc[0] for desc in cur.description]
        rows = [
            {col: serialise(val) for col, val in zip(cols, row)}
            for row in cur.fetchall()
        ]
    return cols, rows


def main():
    dry_run = "--dry-run" in sys.argv
    overwrite = "--overwrite" in sys.argv

    host = os.environ.get("DBT_RW_HOST", "localhost")
    port = int(os.environ.get("DBT_RW_PORT", "4566"))
    user = os.environ.get("DBT_RW_USER", "root")
    password = os.environ.get("DBT_RW_PASSWORD", "")
    dbname = os.environ.get("DBT_RW_DBNAME", "dev")

    EXPECTED_DIR.mkdir(parents=True, exist_ok=True)

    sink_files = sorted(SINKS_DIR.glob("snk_*.sql"))
    if not sink_files:
        print(f"No sink SQL files found in {SINKS_DIR}", file=sys.stderr)
        sys.exit(1)

    conn = psycopg2.connect(host=host, port=port, user=user, password=password, dbname=dbname)
    conn.autocommit = True

    generated = 0
    skipped = 0

    # Filter by --select if provided
    selected_targets = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    
    for sink_path in sink_files:
        sink_name = sink_path.stem  # e.g. snk_energyconsumption_kundeportal
        
        if selected_targets and sink_name not in selected_targets:
            continue

        out_json = EXPECTED_DIR / f"{sink_name}.json"
        out_meta = EXPECTED_DIR / f"{sink_name}.test.json"

        # Skip if exists and not overwriting
        if out_json.exists() and not overwrite:
            print(f"  SKIP {sink_name}: {out_json.name} exists (use --overwrite to replace)")
            skipped += 1
            continue

        sql = sink_path.read_text(encoding="utf-8")
        mart = extract_mart_ref(sql) or sink_name # Use as fallback

        print(f"  {sink_name} ...", end=" ", flush=True)

        try:
            # Query the sink itself
            cols, rows = query_mart(conn, sink_name)
        except Exception as exc:
            print(f"QUERY ERROR: {exc}")
            skipped += 1
            continue

        # Determine blacklist: always-blacklisted + any col that looks like a timestamp seed
        blacklist = sorted(ALWAYS_BLACKLIST & {c.lower() for c in cols})

        if dry_run:
            print(f"DRY ({len(rows)} rows, blacklist={blacklist})")
        else:
            out_json.write_text(
                json.dumps(rows, indent=2, ensure_ascii=False, default=str),
                encoding="utf-8",
            )
            meta = {"mart": mart, "blacklist": blacklist}
            out_meta.write_text(
                json.dumps(meta, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )
            print(f"OK ({len(rows)} rows, blacklist={blacklist})")

        generated += 1

    conn.close()

    print(f"\nBootstrapped {generated} expected_data files. Skipped {skipped}.")
    if generated > 0 and not dry_run:
        print("Review the generated files, then commit them as your E2E baseline.")


if __name__ == "__main__":
    main()
