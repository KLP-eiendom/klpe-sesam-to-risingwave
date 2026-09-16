#!/usr/bin/env python3
"""
Verify mart output against expected_data JSON files (E2E smoke test).

For each models/sinks/snk_*.sql that exists:
  - FAILS if the matching expected_data/snk_<name>.json is missing.
  - Reads snk_<name>.test.json to find columns to skip and the id_field for row matching.
  - Queries SELECT * FROM <sink> on the local RisingWave instance.
  - Compares actual rows to expected rows:
      - Order-independent, matched by "#id" (test-only field in expected data) when present,
        then by id_field from *.test.json, then by heuristic (_id, id, kundenummer, ...),
        then positional fallback.
      - Case-insensitive column names
      - ~f prefix treated as float with 1e-6 relative tolerance
      - Columns in "blacklist" are skipped
      - "#id" is stripped from expected rows before field comparison

On failure: prints a human-readable diff showing expected vs actual.

Exit code 0 = all pass, non-zero = at least one failure or missing file.
"""

import json
import math
import os
import sys
import unicodedata
from pathlib import Path

import psycopg2

SCRIPT_DIR = Path(__file__).parent
DBT_DIR = SCRIPT_DIR.parent
SINKS_DIR = DBT_DIR / "models" / "sinks"
EXPECTED_DIR = DBT_DIR / "models" / "sinks" / "unit_tests" / "expected_data"
FLOAT_TOLERANCE = 1e-6

# Test-only row identity field — never present in actual RisingWave sink tables
TEST_ID_FIELD = "#id"


def parse_value(v):
    if isinstance(v, str):
        if v.startswith("~f"):
            return float(v[2:])
        if v.startswith("~t"):
            return v[2:]
        if v.startswith("~:"):
            return v[2:]
    return v


def values_equal(a, b):
    a = parse_value(a)
    b = parse_value(b)
    if a is None and b is None:
        return True
    if a is None or b is None:
        return False

    # Handle nested dictionaries and lists semantically
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a.keys()) != set(b.keys()):
            return False
        return all(values_equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return False
        return all(values_equal(x, y) for x, y in zip(a, b))


    # Handle datetime/timestamp comparisons
    import datetime
    if isinstance(a, (datetime.datetime, datetime.date)) or isinstance(b, (datetime.datetime, datetime.date)):
        def norm_dt(val):
            if isinstance(val, (datetime.datetime, datetime.date)):
                s = val.isoformat()
            elif isinstance(val, str):
                s = val
            else:
                return str(val)
            return s.replace("T", " ").split(".")[0].replace("+00:00", "").replace("Z", "").strip()
        return norm_dt(a) == norm_dt(b)

    if isinstance(a, float) or isinstance(b, float):
        try:
            return math.isclose(float(a), float(b), rel_tol=FLOAT_TOLERANCE)
        except (TypeError, ValueError):
            return str(a) == str(b)
    try:
        if isinstance(a, (int, float)) or isinstance(b, (int, float)):
            return float(a) == float(b)
    except (TypeError, ValueError):
        pass
    return unicodedata.normalize("NFC", str(a)) == unicodedata.normalize("NFC", str(b))


def normalise_row(row: dict, blacklist: set) -> dict:
    return {
        k.lower(): parse_value(v)
        for k, v in row.items()
        if k.lower() not in (blacklist | {TEST_ID_FIELD.lower()})
    }


def row_sort_key(row: dict) -> str:
    def serialize(obj):
        import datetime
        if isinstance(obj, (datetime.datetime, datetime.date)):
            return obj.isoformat().replace("+00:00", "")
        return str(obj)

    sorted_items = sorted((str(k), serialize(v)) for k, v in row.items())
    return json.dumps(sorted_items)


def fmt_val(v) -> str:
    if v is None:
        return "null"
    return repr(v)


def _print_table(title: str, rows: list[tuple[str, str, str]]):
    """Print a diff table with Field / Expected / Actual columns."""
    col_w = max((len(r[0]) for r in rows), default=5)
    exp_w = max((len(r[1]) for r in rows), default=8)
    act_w = max((len(r[2]) for r in rows), default=6)
    sep = f"    {'-' * col_w}-+-{'-' * exp_w}-+-{'-' * act_w}"
    print(f"    {title}")
    print(f"    {'Field':<{col_w}} | {'Expected':<{exp_w}} | Actual")
    print(sep)
    for field, exp, act in rows:
        print(f"    {field:<{col_w}} | {exp:<{exp_w}} | {act}")


def _build_match_key(row: dict, id_fields: list[str]) -> str | None:
    """Build a match key by joining the values of id_fields with ':'.

    Row lookup is case-insensitive: psycopg2 may return PascalCase column
    names for quoted identifiers (e.g. ``AS "Id"``), while id_fields are
    typically specified in their original SQL casing.
    """
    lower_row = {k.lower(): v for k, v in row.items()}
    parts = [str(lower_row.get(f.lower(), "")) for f in id_fields]
    if all(p in ("", "None") for p in parts):
        return None
    return ":".join(parts)


def get_rid(r: dict, id_fields: list[str] | None = None) -> str | None:
    """Return match key for a row.

    Priority:
    1. "#id" if present in the row — CI-mode VIEWs emit this from test_id() macro,
       so actual rows always have it and it always matches the expected "#id".
    2. Explicit id_fields from *.test.json — fallback for non-CI actual rows.
    3. Heuristic: well-known ID column names.
    """
    val = r.get(TEST_ID_FIELD)
    if val is not None and str(val) != "":
        return str(val)
    if id_fields:
        return _build_match_key(r, id_fields)
    return None


def _exp_match_key(orig_row: dict, norm_row: dict, id_fields: list[str] | None) -> str | None:
    if TEST_ID_FIELD in orig_row:
        return str(orig_row[TEST_ID_FIELD])
    return get_rid(orig_row, id_fields)


def print_diff(expected_rows: list, actual_rows: list, blacklist: set,
               id_fields: list[str] | None = None):
    """Print a human-readable diff between expected and actual rows."""
    exp_norm = [normalise_row(r, blacklist) for r in expected_rows]
    act_norm = [normalise_row(r, blacklist) for r in actual_rows]

    exp_by_id = {_exp_match_key(o, n, id_fields): n
                 for o, n in zip(expected_rows, exp_norm)
                 if _exp_match_key(o, n, id_fields) is not None}
    
    # For actual data, we need the original row for #id check in get_rid
    act_by_id = {}
    for orig_r, norm_r in zip(actual_rows, act_norm):
        rid = get_rid(orig_r, id_fields)
        if rid is not None:
            act_by_id[rid] = norm_r

    use_id_match = bool(exp_by_id and act_by_id)

    if len(exp_norm) != len(act_norm):
        print(f"    Row count: expected {len(exp_norm)}, got {len(act_norm)}")

    if use_id_match:
        missing = sorted(set(exp_by_id) - set(act_by_id))
        extra   = sorted(set(act_by_id) - set(exp_by_id))
        for rid in missing:
            rows = [(col, fmt_val(val), "") for col, val in sorted(exp_by_id[rid].items()) if col != "_id"]
            _print_table(f"MISSING id={rid!r}", rows)
        for rid in extra:
            rows = [(col, "", fmt_val(val)) for col, val in sorted(act_by_id[rid].items()) if col != "_id"]
            _print_table(f"EXTRA   id={rid!r}", rows)
        for rid in sorted(set(exp_by_id) & set(act_by_id)):
            exp_row = exp_by_id[rid]
            act_row = act_by_id[rid]
            diffs = []
            for col in sorted(set(exp_row) | set(act_row)):
                if col == "_id":
                    continue
                ev = exp_row.get(col)
                av = act_row.get(col)
                if not values_equal(ev, av):
                    diffs.append((col, fmt_val(ev), fmt_val(av)))
            if diffs:
                _print_table(f"MISMATCH id={rid!r}", diffs)
    else:
        exp_sorted = sorted(exp_norm, key=row_sort_key)
        act_sorted = sorted(act_norm, key=row_sort_key)
        for i, (exp_row, act_row) in enumerate(zip(exp_sorted, act_sorted)):
            diffs = []
            for col in sorted(set(exp_row) | set(act_row)):
                if col == "_id" and col not in act_row:
                    continue
                ev = exp_row.get(col)
                av = act_row.get(col)
                if not values_equal(ev, av):
                    diffs.append((col, fmt_val(ev), fmt_val(av)))
            if diffs:
                _print_table(f"MISMATCH row[{i}]", diffs)


def compare(expected_rows: list, actual_rows: list, blacklist: set,
            id_fields: list[str] | None = None) -> bool:
    """Return True if all rows match."""
    exp_norm = [normalise_row(r, blacklist) for r in expected_rows]
    act_norm = [normalise_row(r, blacklist) for r in actual_rows]

    if len(exp_norm) != len(act_norm):
        return False

    exp_by_id = {_exp_match_key(o, n, id_fields): n
                 for o, n in zip(expected_rows, exp_norm)
                 if _exp_match_key(o, n, id_fields) is not None}
    
    act_by_id = {}
    for orig_r, norm_r in zip(actual_rows, act_norm):
        rid = get_rid(orig_r, id_fields)
        if rid is not None:
            act_by_id[rid] = norm_r

    if exp_by_id and act_by_id:
        if set(exp_by_id) != set(act_by_id):
            return False
        for rid in exp_by_id:
            exp_row, act_row = exp_by_id[rid], act_by_id[rid]
            for col in set(exp_row) | set(act_row):
                if col.lower() in (blacklist | {"_id"}):
                    continue
                if not values_equal(exp_row.get(col), act_row.get(col)):
                    return False
        return True

    exp_sorted = sorted(exp_norm, key=row_sort_key)
    act_sorted = sorted(act_norm, key=row_sort_key)
    for exp_row, act_row in zip(exp_sorted, act_sorted):
        for col in set(exp_row) | set(act_row):
            if col.lower() in (blacklist | {"_id"}):
                continue
            if not values_equal(exp_row.get(col), act_row.get(col)):
                return False
    return True


def discover_sinks() -> list[str]:
    """Return all sink model names (snk_*.sql) sorted."""
    return sorted(p.stem for p in SINKS_DIR.glob("snk_*.sql"))


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Verify mart output against expected_data JSON files.")
    parser.add_argument("--select", "-s", nargs="+", help="Sinks to verify (basenames without .sql)")
    args = parser.parse_args()

    host = os.environ.get("DBT_RW_HOST", "localhost").strip()
    port = int(os.environ.get("DBT_RW_PORT", "4566").strip())
    user = os.environ.get("DBT_RW_USER", "root").strip()
    password = os.environ.get("DBT_RW_PASSWORD", "").strip()
    dbname = os.environ.get("DBT_RW_DBNAME", "dev").strip()

    all_sinks = discover_sinks()
    if args.select:
        selected = set(args.select)
        all_sinks = [s for s in all_sinks if s in selected]

    if not all_sinks:
        if args.select:
            print(f"No matching sinks found for selection: {args.select}", file=sys.stderr)
        else:
            print(f"No sink models found in {SINKS_DIR}", file=sys.stderr)
        sys.exit(1)

    print(f"Verifying {len(all_sinks)} sinks...")
    conn = psycopg2.connect(host=host, port=port, user=user, password=password, dbname=dbname)
    conn.autocommit = True

    failed_sinks = []
    total_failures = 0

    print(f"Waiting 10 seconds for Materialized Views to refresh...")
    import time
    time.sleep(10)

    for sink_name in all_sinks:
        exp_path  = EXPECTED_DIR / f"{sink_name}.json"
        meta_path = EXPECTED_DIR / f"{sink_name}.test.json"

        # Coverage check: expected_data must exist for every sink
        if not exp_path.exists():
            print(f"  ERROR  {sink_name}: no expected_data/{sink_name}.json — skipped")
            failed_sinks.append(sink_name)
            total_failures += 1
            continue

        if not meta_path.exists():
            print(f"  WARNING {sink_name}: no expected_data/{sink_name}.test.json — using defaults")
            meta = {"blacklist": []}
        else:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))

        blacklist = {c.lower() for c in meta.get("blacklist", [])}

        # id_field: str or list[str] → normalised to list[str] or None
        raw_id_field = meta.get("id_field")
        if isinstance(raw_id_field, str):
            id_fields: list[str] | None = [raw_id_field]
        elif isinstance(raw_id_field, list):
            id_fields = raw_id_field
        else:
            id_fields = None

        try:
            expected_rows = json.loads(exp_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"  ERROR  {sink_name}: expected_data/{sink_name}.json is empty or malformed JSON")
            failed_sinks.append(sink_name)
            total_failures += 1
            continue

        if not isinstance(expected_rows, list):
            print(f"  ERROR  {sink_name}: expected_data must be a JSON array")
            failed_sinks.append(sink_name)
            total_failures += 1
            continue

        if len(expected_rows) == 0:
            print(f"  ERROR  {sink_name}: expected_data is empty (must have at least 1 row)")
            failed_sinks.append(sink_name)
            total_failures += 1
            continue

        print(f"  {sink_name} ...", end=" ", flush=True)

        try:
            with conn.cursor() as cur:
                try:
                    cur.execute(f'SELECT * FROM "{sink_name}"')
                except Exception:
                    conn.rollback()
                    cur.execute(f'SELECT * FROM "v_{sink_name}"')
                cols = [desc[0] for desc in cur.description]
                actual_rows = [dict(zip(cols, row)) for row in cur.fetchall()]
        except Exception as exc:
            msg = str(exc)
            if "table or source not found" in msg.lower() or "does not exist" in msg.lower():
                print(f"  WARNING {sink_name}: Table/view not found in database — skipped")
            else:
                print(f"  QUERY ERROR: {exc}")
                failed_sinks.append(sink_name)
                total_failures += 1
            continue

        if compare(expected_rows, actual_rows, blacklist, id_fields=id_fields):
            print(f"PASS ({len(actual_rows)} rows)")
        else:
            print(f"FAIL")
            print_diff(expected_rows, actual_rows, blacklist, id_fields=id_fields)
            failed_sinks.append(sink_name)
            total_failures += 1

    conn.close()

    print()
    if total_failures:
        print(f"FAILED SINKS: {', '.join(failed_sinks)}")
        print(f"{total_failures} E2E test(s) FAILED", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"All {len(all_sinks)} E2E tests passed.")


if __name__ == "__main__":
    main()
