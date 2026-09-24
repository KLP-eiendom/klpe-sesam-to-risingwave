#!/usr/bin/env python3
"""
verify_sink_values.py — STRICT ID-PARITY + value comparison between RisingWave sink output
and the corresponding Sesam source dataset, for the Sesam→RisingWave migration.

The migration requires the primary-key IDs to be IDENTICAL between Sesam and RisingWave.
This tool therefore matches rows STRICTLY on the sink's id_field (the destination primary
key) — it does NOT normalize, strip, or transform keys to force a match. An id that doesn't
line up between the two platforms is itself the finding (ID_MISMATCH): it is fixed in the
RisingWave sink so it emits the id Sesam wrote — never worked around in this script.

It is the value-level sibling of verify_sink_counts.py (Tier 1, counts); Tier 1 proves *how
many* rows each side produces, this proves *which ids* and *whether the values* match.
Strictly READ-ONLY (SELECT on RisingWave, GET on Sesam — no writes). Statuses:

  PARITY          every id matched AND all matched rows' values equal  (✓ verified)
  DIFFERENCES     all ids matched, but some field VALUES differ          (investigate)
  ID_MISMATCH     RW-only and/or Sesam-only ids exist — the actionable "fix RisingWave"
                  finding. The unmatched ids can be written to the *_id_mismatches.csv worklist with --id-mismatches.
  RW_EMPTY        RisingWave sink output is empty in this env (mart not backfilled here).
  SESAM_EMPTY     Sesam source dataset has 0 current entities.
  SESAM_MISSING   Sesam source dataset not found (404) — mapping wrong or pipe removed.
  SESAM_DOWN      Sesam node returned 503 (paused/unavailable).
  NO_SESAM_SOURCE no Sesam endpoint pipe for this sink (e.g. KlpeFindable) — RW-only, intentional.
  NOT_COMPILED    sink has no compiled SELECT — run dbt compile.
  NO_ID_FIELD     <sink>.test.json has no id_field, or it isn't a real output column.
  SKIPPED_LARGE   dataset exceeds --max-rows for a batch full-compare — run it with --select.
  ERROR           an unexpected read error (message in the detail).

CANDIDATE CAVEAT: RW-only / Sesam-only ids are CANDIDATES, not confirmed bugs. We read the
Sesam *source* dataset (input), because Sesam's endpoint OUTPUT is not readable via its API.
The input keeps Sesam namespace prefixes (e.g. "superoffice-sale:6501") that the destination
output strips ("6501"), so some mismatches are input-vs-output artifacts. Verify each flagged
id against the REAL destination output before changing RisingWave.

How a comparison works, per sink:
  1. RW rows  — SELECT * FROM (<sink's compiled SELECT>) q  → list of dicts.
  2. Sesam rows — page GET /api/datasets/<source_dataset>/entities (current, non-deleted),
     strip the "<dataset>:" key prefix so field names match the RW columns → list of dicts.
  3. Match STRICTLY by the sink's id_field (from <sink>.test.json — a single column or a
     composite list); reconcile the id sets, then compare every non-blacklisted field of the
     matched rows with verify_e2e.py's values_equal (transit prefixes, datetime, float, NULL).

Usage (run from dbt/, after `dbt compile --select tag:sink --target test`):
    python scripts/verify_sink_values.py test                       # all sinks → status table
    python scripts/verify_sink_values.py test --select snk_firma_forvalter
    python scripts/verify_sink_values.py test --select snk_firma_forvalter,snk_leieobjekt_forvalter
    python scripts/verify_sink_values.py test --max-diffs 50

    env defaults to 'test'. prod requires --confirm-prod.

Reuses (does NOT modify): verify_sink_counts.py (Vault/cred bootstrap, sink↔Sesam map,
compiled-SELECT extraction) and verify_e2e.py (parse_value/values_equal/normalise_row/get_rid).
"""

import argparse
import csv
import json
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import time
from datetime import datetime, timezone
from pathlib import Path

import verify_sink_counts as vc
from verify_e2e import get_rid, normalise_row, values_equal

TEST_JSON_DIR = vc.DBT_DIR / "models" / "sinks" / "unit_tests" / "expected_data"

# Sesam entity housekeeping + RW synthesized columns — never business data, always skipped.
SYSTEM_BLACKLIST = {
    "_id", "_deleted", "_hash", "_previous", "_ts", "_updated", "$ids", "rdf:type",
    "created", "lastupdated",
}

# Output sort order = ascending criticality (top = least critical, bottom = most).
# Verified-good first, then verified-with-findings, then "couldn't compare" ranked by how
# likely it hides a real problem (key issues > config > Sesam-side > env > intentional),
# with ERROR last. Reorder this list to change the sort. DIFFERENCES sub-sorts fewest→most diffs.
STATUS_RANK = {
    "PARITY": 0,
    "DIFFERENCES": 1,
    "ID_MISMATCH": 2,
    "NO_ID_FIELD": 3,
    "SESAM_MISSING": 4,
    "SESAM_DOWN": 5,
    "SESAM_EMPTY": 6,
    "RW_EMPTY": 7,
    "SKIPPED_LARGE": 8,
    "NO_SESAM_SOURCE": 9,
    "ERROR": 10,
}


def sort_key(r):
    """(criticality rank, field-diff count asc, missing+extra asc, sink) — see STATUS_RANK."""
    rank = STATUS_RANK.get(r["status"], 99)
    fm = r.get("field_mismatch_count") or 0
    me = (len(r["missing_in_rw"]) + len(r["extra_in_rw"])) if isinstance(r.get("missing_in_rw"), list) else 0
    return (rank, fm, me, r["sink"])


def _ssl_ctx():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


# ── Sesam paging ───────────────────────────────────────────────────────────────


def sesam_get_page(base, token, dataset, since=None, limit=1000):
    """One page of current, non-deleted entities. Returns (entities, http_status_or_None).
    http_status is set (404/503/…) and entities=[] when the GET failed."""
    b = base.rstrip("/")
    if b.endswith("/api"):
        b = b[: -len("/api")]
    params = f"history=false&deleted=false&limit={limit}"
    if since is not None:
        params += f"&since={urllib.parse.quote(str(since))}"
    url = f"{b}/api/datasets/{dataset}/entities?{params}"
    req = urllib.request.Request(
        url, headers={"Authorization": f"bearer {token}", "Accept": "application/json"}
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120, context=_ssl_ctx()) as resp:
                return json.loads(resp.read()), None
        except urllib.error.HTTPError as exc:
            if exc.code in (502, 503, 504, 429) and attempt < 2:
                time.sleep(2 ** attempt)
                continue
            return [], exc.code
        except Exception as exc:  # noqa: BLE001
            if attempt < 2:
                time.sleep(2 ** attempt)
                continue
            return [], str(exc)
    return [], "Max retries exceeded"


def strip_prefix(ent, prefix):  # `prefix` kept for call-site compat; no longer the sole prefix
    """Strip the Sesam namespace from each property key so names match the RW columns.

    A field carries the namespace of the pipe that CREATED it. For copy-*-chained datasets that
    is the upstream SOURCE (e.g. 'forvalter-brukerrolle:Id', 'd365-prosjekt:prosjekt_id'), NOT
    the endpoint-feeding dataset name. So strip any single leading '<ns>:' rather than only
    `prefix`. Leave system fields ('_*') and RDF metadata ('rdf:*') untouched; first occurrence
    wins on the rare localname collision (multi-namespace merges)."""
    out = {}
    for k, v in ent.items():
        if k.startswith("_") or k.startswith("rdf:"):
            nk = k
        elif ":" in k:
            nk = k.split(":", 1)[1]
        else:
            nk = k
        out.setdefault(nk, v)
    return out


def fetch_sesam_rows(base, token, dataset, page_limit=1000, hard_cap=300000):
    """All current non-deleted entities, prefix-stripped, deduped by _id (latest _ts).
    Returns (rows, status). status is None on success, else an http code / message."""
    prefix = dataset + ":"
    by_id = {}
    since = None
    fetched = 0
    while fetched < hard_cap:
        page, status = sesam_get_page(base, token, dataset, since, page_limit)
        if status is not None:
            return [], status
        if not page:
            break
        for ent in page:
            if ent.get("_deleted"):
                continue
            _id = ent.get("_id")
            ts = ent.get("_ts", 0) or 0
            if _id in by_id and by_id[_id][0] >= ts:
                continue
            by_id[_id] = (ts, strip_prefix(ent, prefix))
        fetched += len(page)
        if fetched > 0 and fetched % 5000 == 0:
            print(f"    [{dataset}] fetched {fetched} entities from Sesam...", flush=True)
        last_updated = page[-1].get("_updated")
        if last_updated is None or len(page) < page_limit:
            if fetched >= 5000:
                print(f"    [{dataset}] total fetched {fetched} entities.", flush=True)
            break
        since = last_updated
    return [row for _ts, row in by_id.values()], None


# ── RisingWave fetch ─────────────────────────────────────────────────────────────


def fetch_rw_rows(cur, compiled_sql_path):
    sql = vc.extract_select(compiled_sql_path.read_text(encoding="utf-8"))
    cur.execute(f"SELECT * FROM (\n{sql}\n) AS _sink_rows")
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def rw_output_columns(cur, compiled_sql_path):
    """Output column names of the sink's SELECT (cheap — LIMIT 0, no rows)."""
    sql = vc.extract_select(compiled_sql_path.read_text(encoding="utf-8"))
    cur.execute(f"SELECT * FROM (\n{sql}\n) AS _cols LIMIT 0")
    return [d[0] for d in cur.description]


def resolve_id_columns(id_fields, output_cols):
    """Map each id_field to its actual output column (case-insensitive).
    Returns (resolved_cols, missing). missing is the id_fields with no output column."""
    lower = {c.lower(): c for c in output_cols}
    resolved, missing = [], []
    for f in id_fields:
        if f.lower() in lower:
            resolved.append(lower[f.lower()])
        else:
            missing.append(f)
    return resolved, missing


def fetch_rw_id_set(cur, compiled_sql_path, resolved_cols, id_fields):
    """Cheap: select only the (resolved) id column(s) and build the set of match keys."""
    sql = vc.extract_select(compiled_sql_path.read_text(encoding="utf-8"))
    cols_sql = ", ".join(f'"{c}"' for c in resolved_cols)
    cur.execute(f"SELECT {cols_sql} FROM (\n{sql}\n) AS _ids")
    names = [d[0] for d in cur.description]
    ids = set()
    for row in cur.fetchall():
        rid = get_rid(dict(zip(names, row)), id_fields)
        if rid not in (None, ""):
            ids.add(rid)
    return ids


# ── Comparison (structured, on verify_e2e's engine) ────────────────────────────


def _index_by_key(rows, id_fields, blacklist):
    out = {}
    for r in rows:
        rid = get_rid(r, id_fields)
        if rid not in (None, ""):
            out[rid] = normalise_row(r, blacklist)
    return out


def compare_values(rw_rows, sesam_rows, id_fields, blacklist, max_diffs):
    rw_by = _index_by_key(rw_rows, id_fields, blacklist)
    se_by = _index_by_key(sesam_rows, id_fields, blacklist)
    missing = sorted(set(se_by) - set(rw_by))   # in Sesam, absent from RW
    extra = sorted(set(rw_by) - set(se_by))     # in RW, absent from Sesam
    common = set(rw_by) & set(se_by)
    diffs, rows_mm, field_mm = [], 0, 0
    for rid in sorted(common):
        rw_row, se_row = rw_by[rid], se_by[rid]
        rd = []
        for col in sorted(set(rw_row) | set(se_row)):
            if col == "_id":
                continue
            rv, sv = rw_row.get(col), se_row.get(col)
            if not values_equal(sv, rv):
                rd.append((col, rv, sv))
        if rd:
            rows_mm += 1
            field_mm += len(rd)
            for col, rv, sv in rd:
                if len(diffs) < max_diffs:
                    diffs.append({"id": rid, "field": col, "rw": _jsonable(rv), "sesam": _jsonable(sv)})
    return {"matched": len(common), "missing_in_rw": missing, "extra_in_rw": extra,
            "rows_with_mismatch": rows_mm, "field_mismatch_count": field_mm, "diffs": diffs}


def _jsonable(v):
    if isinstance(v, datetime):
        return v.isoformat()
    try:
        json.dumps(v)
        return v
    except (TypeError, ValueError):
        return str(v)


# ── Per-sink evaluation ──────────────────────────────────────────────────────────


def evaluate_sink(sink, env, cur, sesam_url, sesam_token, smap, args):
    """Return a result dict: {sink, sesam_dataset, status, detail, ...metrics}."""
    def res(status, detail, **extra):
        return {"sink": sink, "sesam_dataset": smap.get(sink), "status": status,
                "detail": detail, **extra}

    if sink in vc.SINKS_WITHOUT_SESAM:
        return res("NO_SESAM_SOURCE",
                   "No Sesam endpoint pipe for this sink (e.g. KlpeFindable) — RisingWave-only "
                   "target; no Sesam data exists to compare. Likely intentional.")
    if sink not in smap:
        return res("NO_SESAM_SOURCE",
                   "Sink not in sink_sesam_map.json — no known Sesam source dataset. "
                   "Add a mapping if a Sesam counterpart exists.")
    dataset = smap[sink]

    compiled = vc.find_compiled_sql(sink)
    if compiled is None:
        return res("NOT_COMPILED", f"No compiled SELECT — run: dbt compile --select {sink} --target {env}")

    meta_path = TEST_JSON_DIR / f"{sink}.test.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
    # STRICT ID PARITY: match rows ONLY on the sink's id_field — the destination primary key,
    # the same id Sesam wrote. A single column or a composite list. We deliberately do NOT
    # normalize/strip/transform the key to force a match: a non-overlapping id IS the finding
    # (ID_MISMATCH), fixed in the RisingWave sink, never worked around here.
    raw_match = meta.get("id_field")
    match_fields = [raw_match] if isinstance(raw_match, str) else (raw_match if isinstance(raw_match, list) else None)
    if not match_fields:
        return res("NO_ID_FIELD", f"{sink}.test.json has no id_field — cannot match rows by primary key.")
    blacklist = SYSTEM_BLACKLIST | {c.lower() for c in meta.get("blacklist", [])}

    # Resolve id_field to the sink's actual output columns (the SELECT is case-sensitive).
    try:
        out_cols = rw_output_columns(cur, compiled)
    except Exception as exc:  # noqa: BLE001
        return res("ERROR", f"RisingWave read failed: {str(exc).splitlines()[0]}")
    resolved, missing = resolve_id_columns(match_fields, out_cols)
    if missing:
        return res("NO_ID_FIELD",
                   f"id_field {missing} is not an output column of this sink "
                   f"(columns: {sorted(out_cols)}) — fix id_field in {sink}.test.json to a real "
                   f"output column.")

    # RW id set (cheap) → empty guard.
    try:
        rw_ids = fetch_rw_id_set(cur, compiled, resolved, match_fields)
    except Exception as exc:  # noqa: BLE001
        return res("ERROR", f"RisingWave read failed: {str(exc).splitlines()[0]}")
    if not rw_ids:
        return res("RW_EMPTY",
                   f"RisingWave sink output is empty in '{env}' (upstream mart has 0 rows). "
                   "Not backfilled in this environment — cannot compare. May be expected in "
                   "test, or indicate missing data.", rw_rows=0)

    # Sesam readability (first page is enough to detect 404 / 503 / empty).
    page, status = sesam_get_page(sesam_url, sesam_token, dataset, limit=args.sesam_limit)
    if status == 404:
        return res("SESAM_MISSING", f"Sesam source dataset '{dataset}' not found (404) — mapping wrong or pipe removed.")
    if status == 503:
        return res("SESAM_DOWN", f"Sesam node returned 503 for '{dataset}' (paused/unavailable) — retry when up.")
    if status is not None:
        return res("ERROR", f"Sesam read failed for '{dataset}': {status}")
    if not page:
        return res("SESAM_EMPTY", f"Sesam source dataset '{dataset}' has 0 current entities.")

    # Size guard before the full fetch + compare.
    if len(rw_ids) > args.max_rows:
        return res("SKIPPED_LARGE",
                   f"RW has {len(rw_ids)} rows (> --max-rows {args.max_rows}); skipped full fetch "
                   f"in batch. Run individually: --select {sink} --max-rows {len(rw_ids)+1}.",
                   rw_rows=len(rw_ids))

    # Full fetch on both sides → strict id-keyed reconciliation + value compare of matched rows.
    try:
        rw_rows = fetch_rw_rows(cur, compiled)
        sesam_rows, st = fetch_sesam_rows(sesam_url, sesam_token, dataset, page_limit=args.sesam_limit)
        if st is not None:
            return res("ERROR", f"Sesam full fetch failed for '{dataset}': {st}")
    except Exception as exc:  # noqa: BLE001
        return res("ERROR", f"full fetch failed: {exc}")

    cmp = compare_values(rw_rows, sesam_rows, match_fields, blacklist, args.max_diffs)
    n_rw_only = len(cmp["extra_in_rw"])        # ids in RW, absent from Sesam
    n_sesam_only = len(cmp["missing_in_rw"])   # ids in Sesam, absent from RW
    n_field = cmp["field_mismatch_count"]      # field diffs among the matched rows
    if n_rw_only or n_sesam_only:
        status_out = "ID_MISMATCH"
    elif n_field:
        status_out = "DIFFERENCES"
    else:
        status_out = "PARITY"
    detail = (f"{cmp['matched']} matched | {n_rw_only} RW-only id, {n_sesam_only} Sesam-only id "
              f"| {n_field} field diffs in matched rows")
    return res(status_out, detail, rw_rows=len(rw_rows), sesam_rows=len(sesam_rows), **cmp)


# ── CSV output (Excel-friendly: UTF-8 BOM + configurable delimiter) ─────────────


def write_csv_reports(results, summary_path, diffs_path, id_mismatch_path, delimiter):
    """Write the per-sink summary and the per-field diffs of MATCHED rows. When id_mismatch_path
    is set, also write the per-id ID-mismatch worklist (off by default — large). Returns the paths."""
    # Summary: one row per sink.
    with open(summary_path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=delimiter)
        w.writerow(["criticality", "sink", "status", "sesam_dataset", "rw_rows", "sesam_rows",
                    "matched", "rw_only", "sesam_only", "rows_with_mismatch",
                    "field_mismatches", "detail"])
        for r in results:
            w.writerow([
                STATUS_RANK.get(r["status"], 99),
                r["sink"], r["status"], r.get("sesam_dataset") or "",
                r.get("rw_rows", ""), r.get("sesam_rows", ""), r.get("matched", ""),
                len(r["extra_in_rw"]) if isinstance(r.get("extra_in_rw"), list) else "",
                len(r["missing_in_rw"]) if isinstance(r.get("missing_in_rw"), list) else "",
                r.get("rows_with_mismatch", ""), r.get("field_mismatch_count", ""),
                r.get("detail", ""),
            ])

    # Field diffs: one row per field mismatch among MATCHED rows (capped per sink by --max-diffs).
    with open(diffs_path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=delimiter)
        w.writerow(["sink", "id", "field", "rw_value", "sesam_value"])
        for r in results:
            for d in r.get("diffs", []):
                w.writerow([r["sink"], d["id"], d["field"], d["rw"], d["sesam"]])

    # ID-mismatch worklist: one row per unmatched id. side = rw_only (in RW, not Sesam) or
    # sesam_only (in Sesam, not RW). CANDIDATES — verify against the real destination output
    # before fixing RisingWave (we read the Sesam source/input, not its de-namespaced output).
    if id_mismatch_path is not None:
        with open(id_mismatch_path, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f, delimiter=delimiter)
            w.writerow(["sink", "id", "side"])
            for r in results:
                for rid in (r["extra_in_rw"] if isinstance(r.get("extra_in_rw"), list) else []):
                    w.writerow([r["sink"], rid, "rw_only"])
                for rid in (r["missing_in_rw"] if isinstance(r.get("missing_in_rw"), list) else []):
                    w.writerow([r["sink"], rid, "sesam_only"])
    return summary_path, diffs_path, id_mismatch_path


# ── Main ────────────────────────────────────────────────────────────────────────


def main():
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8")
        except Exception:
            pass

    p = argparse.ArgumentParser(description="Strict ID-parity + value comparison: RisingWave vs Sesam.")
    p.add_argument("env", nargs="?", default="test", choices=["dev", "test", "prod"])
    p.add_argument("--select", help="comma-separated sink names; default = all sinks")
    p.add_argument("--max-diffs", type=int, default=40, help="max per-field diffs stored per sink")
    p.add_argument("--id-mismatches", action="store_true",
                   help="also write the per-id ID-mismatch worklist CSV (large; off by default — verify in RW directly)")
    p.add_argument("--sesam-limit", type=int, default=1000, help="Sesam page size")
    p.add_argument("--max-rows", type=int, default=60000, help="skip full compare above this RW row count")
    p.add_argument("--confirm-prod", action="store_true", help="required to target prod")
    p.add_argument("--json", help="JSON artifact path (default verify_sink_values_<env>.json)")
    p.add_argument("--csv-delimiter", default=";",
                   help="CSV delimiter (default ';' for Norwegian Excel; use ',' for standard CSV)")
    args = p.parse_args()
    env = args.env

    if env == "prod" and not args.confirm_prod:
        print("REFUSING to run against prod without --confirm-prod.", file=sys.stderr)
        sys.exit(2)
    if env == "prod":
        print("=" * 70 + "\n  RUNNING AGAINST PRODUCTION (read-only)\n" + "=" * 70)

    smap = vc.load_sink_sesam_map()
    all_sinks = sorted(p2.stem for p2 in vc.SINKS_DIR.glob("snk_*.sql"))
    if args.select:
        want = {s.strip() for s in args.select.split(",") if s.strip()}
        sinks = [s for s in all_sinks if s in want]
    else:
        sinks = all_sinks
    if not sinks:
        print("ERROR: no sinks matched (check --select)", file=sys.stderr)
        sys.exit(1)

    # Credentials (same sources as verify_sink_counts).
    file_env = vc.load_env_file({
        "dev": vc.REPO_ROOT / ".env.development", "test": vc.REPO_ROOT / ".env.test",
        "prod": vc.REPO_ROOT / ".env.production",
    }[env])
    vault_server = (file_env.get("VaultOptions__Server") or "").rstrip("/")
    vault_token = file_env.get("VaultOptions__TokenId") or ""
    if not vault_server or not vault_token:
        print("ERROR: VaultOptions__Server / VaultOptions__TokenId missing from env file", file=sys.stderr)
        sys.exit(1)

    print(f"==> Environment : {env}")
    kdi = vc.vault_read(vault_server, vault_token, f"kdi/{env}")
    sesam_token = kdi.get("SesamAccessInfo:AuthToken", "")
    sesam_url = (kdi.get("SesamAccessInfo:SesamBaseUrl") or kdi.get("SesamAccessInfo:NodeUrl")
                 or kdi.get("SesamAccessInfo:BaseUrl") or "")
    rw = vc.vault_read(vault_server, vault_token, f"risingwave/{env}", optional=True)
    if rw and rw.get("DBT_RW_HOST"):
        rw_host, rw_user = rw["DBT_RW_HOST"], rw.get("DBT_RW_USER", "root")
        rw_password, rw_dbname = rw.get("DBT_RW_PASSWORD", ""), rw.get("DBT_RW_DBNAME", env)
    else:
        rw_host, rw_user = kdi.get("RisingWaveSettings:SqlHost", ""), kdi.get("RisingWaveSettings:SqlUsername", "root")
        rw_password, rw_dbname = kdi.get("RisingWaveSettings:SqlPassword", ""), env
    if not (sesam_token and sesam_url and rw_host):
        print("ERROR: missing Sesam or RisingWave connection details from Vault", file=sys.stderr)
        sys.exit(1)

    try:
        import psycopg2
    except ImportError:
        print("ERROR: psycopg2 not installed — run: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)
    conn = psycopg2.connect(host=rw_host, port=4566, dbname=rw_dbname, user=rw_user,
                            password=rw_password, sslmode="require", connect_timeout=20)
    conn.autocommit = True
    print(f"==> RisingWave  : {rw_host}:4566/{rw_dbname}")
    print(f"==> Sesam       : {sesam_url}")
    print(f"==> Evaluating {len(sinks)} sink(s) ...\n")

    results = []
    with conn.cursor() as cur:
        for sink in sinks:
            try:
                r = evaluate_sink(sink, env, cur, sesam_url, sesam_token, smap, args)
            except Exception as exc:  # noqa: BLE001 — never let one sink kill the batch
                r = {"sink": sink, "sesam_dataset": smap.get(sink), "status": "ERROR",
                     "detail": f"unexpected: {exc}"}
            results.append(r)
    conn.close()

    # Sort by ascending criticality (see STATUS_RANK); shared by table, JSON, and CSVs.
    results.sort(key=sort_key)

    # ── Table ────────────────────────────────────────────────────────────────────
    col_sink = max(len(r["sink"]) for r in results) + 1
    print(f"  {'Sink':<{col_sink}}  {'Status':<15}  Detail / reason")
    print("  " + "-" * (col_sink + 17 + 60))
    from collections import Counter
    tally = Counter()
    for r in results:
        tally[r["status"]] += 1
        print(f"  {r['sink']:<{col_sink}}  {r['status']:<15}  {r['detail']}")
    print()
    print("  Summary: " + " | ".join(f"{n} {s}" for s, n in sorted(tally.items())))

    # Per-sink field diffs for matched rows (DIFFERENCES + any ID_MISMATCH that also has them).
    for r in results:
        if r["status"] in ("DIFFERENCES", "ID_MISMATCH") and r.get("diffs"):
            print(f"\n  --- {r['sink']}: first {len(r['diffs'])} field diffs (id | field | RW | Sesam) ---")
            for d in r["diffs"]:
                print(f"    {d['id']!r:28} {d['field']:<22} RW={d['rw']!r:28} Sesam={d['sesam']!r}")

    artifact = {"env": env, "generated_at": datetime.now(timezone.utc).isoformat(),
                "summary": dict(tally), "results": results}
    out = Path(args.json) if args.json else (vc.DBT_DIR / f"verify_sink_values_{env}.json")
    out.write_text(json.dumps(artifact, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n==> Wrote {out}")

    summary_csv = out.with_name(f"verify_sink_values_{env}_summary.csv")
    diffs_csv = out.with_name(f"verify_sink_values_{env}_diffs.csv")
    id_mismatch_csv = (out.with_name(f"verify_sink_values_{env}_id_mismatches.csv")
                       if args.id_mismatches else None)
    write_csv_reports(results, summary_csv, diffs_csv, id_mismatch_csv, args.csv_delimiter)
    print(f"==> Wrote {summary_csv}  (open in Excel — one row per sink)")
    print(f"==> Wrote {diffs_csv}  (one row per field mismatch in matched rows)")
    if id_mismatch_csv is not None:
        print(f"==> Wrote {id_mismatch_csv}  (one row per unmatched id — the fix-RW worklist)")
        print("    NOTE: unmatched ids are CANDIDATES — verify against the real destination output "
              "before changing RisingWave (we read the Sesam source/input, not its de-namespaced output).")


if __name__ == "__main__":
    main()
