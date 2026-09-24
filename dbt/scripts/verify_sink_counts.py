#!/usr/bin/env python3
"""
verify_sink_counts.py — Compare row counts between RisingWave and the corresponding
Sesam dataset, per sink, for the Sesam→RisingWave migration.

This is the sink-level sibling of verify_staging_counts.py. For every sink in
models/sinks/ it reports three counts and flags differences:

  * RW mart  — COUNT(*) of the materialized view the sink reads FROM (no WHERE) — the
               prepared-data layer, the apples-to-apples analog of the Sesam dataset.
  * RW sink  — COUNT(*) of the sink's actual output (its compiled SELECT, post-WHERE/dedup).
  * Sesam    — live (non-deleted) entity count of the Sesam SOURCE dataset.

Status is OK if EITHER the mart OR the sink output matches Sesam (within --tolerance): the
mart catches data coverage; the sink catches sinks where a real WHERE filter (e.g. faktura's
elektronisk=1) or a row-expanding join is what aligns RW with the mapped Sesam dataset.
MISMATCH means NEITHER layer matches. Strictly READ-ONLY (SELECT COUNT(*) on RW, GET on Sesam).

Usage (run from the dbt/ directory):
    # 1. Compile the sink SELECTs for the target environment (read-only):
    dbt compile --select tag:sink --target test

    # 2. Compare counts (writes verify_sink_counts_<env>.csv + .json):
    python scripts/verify_sink_counts.py test
    python scripts/verify_sink_counts.py test --select snk_bygg_forvalter
    python scripts/verify_sink_counts.py test --tolerance 10 --strict

    env defaults to 'test'. Options: dev | test | prod
    prod requires the explicit --confirm-prod flag (no automated/CI run targets prod).

Why count the compiled SELECT (not a live read of the sink)?
    In dev/test/prod the sink renders as a write-only CREATE SINK (unreadable). The
    dbt-compiled SELECT body is the read-only equivalent; extract_select() strips any
    CREATE SINK ... AS header and trailing connector WITH(...) so it wraps in COUNT(*).

Sink -> Sesam SOURCE dataset mapping:
    From scripts/sink_sesam_map.json (generated from the Sesam pipe configs' source.dataset).
    NOTE: the Sesam *-endpoint pipes themselves have sql/rest sinks and are NOT readable
    (HTTP 503); their upstream source dataset is what we read. Sinks absent from the map
    (and the Findable sinks) are reported SKIPPED. Regenerate the map when pipes change.

Vault secrets fetched (KV v1 — paths are CASE-SENSITIVE, note lowercase 'risingwave'):
  kv/risingwave/<env>  ->  DBT_RW_HOST, DBT_RW_USER, DBT_RW_PASSWORD, DBT_RW_DBNAME
                          (falls back to kv/kdi/<env> RisingWaveSettings:* if not readable;
                           but only the kv/risingwave user owns/can SELECT the marts)
  kv/kdi/<env>         ->  SesamAccessInfo:AuthToken, SesamAccessInfo:SesamBaseUrl

Connection: RisingWave (test/prod) is RisingWave Cloud — connect directly to DBT_RW_HOST
on :4566 (SSL). No kubectl port-forward needed.

Requires: pip install psycopg2-binary
"""

import argparse
import csv
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
DBT_DIR = SCRIPT_DIR.parent
REPO_ROOT = DBT_DIR.parent
TEST_JSON_DIR = DBT_DIR / "models" / "sinks" / "unit_tests" / "expected_data"
SINKS_DIR = DBT_DIR / "models" / "sinks"
SINK_SESAM_MAP = SCRIPT_DIR / "sink_sesam_map.json"
COMPILED_GLOB = "target/compiled/*/models/sinks/{sink}.sql"

DEFAULT_TOLERANCE = 5  # |RW - Sesam| <= tolerance => WARN (timing drift), not MISMATCH

# Sinks with no Sesam counterpart (Findable has no Sesam pipe) — reported SKIPPED.
SINKS_WITHOUT_SESAM = {
    "snk_bygg_findable",
    "snk_serviceavtale_findable",
}

# Sinks whose sink_sesam_map.json dataset is the SOURCE feeding an intermediate Sesam pipe
# that applies an additional `field != null` filter *after* the mapped dataset but *before*
# the actual REST/endpoint send — so the mapped dataset's raw count overstates what Sesam
# really emits. We can't read the intermediate/endpoint pipe directly (HTTP 503, same reason
# we read the source dataset at all), so we fetch entities and apply the filter client-side.
# Add an entry here (with a comment citing the intermediate pipe .conf.json) whenever a
# MISMATCH is root-caused to this pattern, so future runs compare correctly out of the box.
SESAM_POST_FILTER_NOT_NULL = {
    # leverandor-omsetning-superoffice-rest.conf.json filters `neq null _S.contactId` between
    # d365-leverandor-omsetning-grouped and the actual SuperOffice POST. Confirmed 2026-07-21:
    # grouped=4666 (3362 with contactId, 1304 without) vs RW mart/sink=3358 — matches within
    # normal pump-lag once the null-contactId rows are excluded.
    "snk_leverandor_omsetning_superoffice": "contactId",
    # user-leko-rest.conf.json filters `neq null _S.companyId` between user-leko and the actual
    # Leko POST. Confirmed 2026-07-22: user-leko=6186 (5581 with companyId, 605 without) vs
    # RW mart/sink=5583 — matches within normal pump-lag once the null-companyId rows are excluded.
    "snk_user_leko": "companyId",
}

# Sinks where the mapped Sesam dataset emits MULTIPLE entities that collapse onto the SAME
# downstream target primary key — either a Sesam merge equality that doesn't collapse two
# source facts into one entity (e.g. a contactId shared by superoffice-contact and
# superoffice-contactsimple that never merge), or several distinct source records
# legitimately mapping to one target row (e.g. several personId records sharing the same
# (contact, email) pair). RW's sink already dedupes to one row per target PK, so the raw
# Sesam entity count overstates what's achievable — the true ceiling is the count of DISTINCT
# key tuples, not the raw row count. Key fields must match the sink's actual primary_key.
# Add an entry here (with the confirmed count breakdown) whenever a MISMATCH is root-caused
# to this pattern, so future runs compare correctly out of the box.
SESAM_DEDUP_KEY = {
    # customer-leko.conf.json merges superoffice-contact + superoffice-contactsimple; the
    # `eq s-c.contactId s-cs.contactId` equality fails to collapse for ~60% of contacts (a
    # Sesam-side merge bug), so the same contactId appears as two separate entities. RW sink
    # primary_key is Id (=contactId). Confirmed 2026-07-21: raw=17757, distinct Id=11075,
    # RW sink=10870.
    "snk_customer_leko": ["Id"],
    # BrukerKunde's MySQL PK is (SoContactId, BrukerId); several superoffice-user personId
    # records can legitimately share the same (contact, email) pair. RW sink already dedupes
    # to the lowest personId per pair (see snk_usercustomer_kundeportal.sql's own comment).
    # Confirmed 2026-07-22: raw=6611, distinct pairs=6519, RW sink=6521.
    "snk_usercustomer_kundeportal": ["SoContactId", "BrukerId"],
    # PersonKonvolutt's MySQL PK is (PersonEpost, KonvoluttId, Type); Verified.eu envelope
    # payloads can list the same owner/recipient more than once (verbatim repeats, or
    # different recipient uids sharing an email) — same class of issue, fixed on the RW side
    # in mrt_verified_personkonvolutt.sql (DISTINCT + ROW_NUMBER), but Sesam's own dataset
    # carries its own duplicates too. Confirmed 2026-07-23: raw=10077, distinct pairs=9648,
    # RW sink=9646.
    "snk_personkonvolutt_forvalter": ["PersonEpost", "KonvoluttId", "Type"],
}

# ── Vault / env helpers (mirrors verify_staging_counts.py) ───────────────────────


def _ssl_ctx():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def load_env_file(path):
    env = {}
    if not path or not os.path.exists(str(path)):
        return env
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            env[key.strip()] = value.strip()
    return env


def vault_read(server, token, path, optional=False):
    """Read a KV v1 secret at `path`. Returns the data dict, or None if optional and 404."""
    url = f"{server}/v1/kv/{path}"
    req = urllib.request.Request(url, headers={"X-Vault-Token": token})
    try:
        with urllib.request.urlopen(req, context=_ssl_ctx()) as resp:
            return json.loads(resp.read()).get("data", {})
    except urllib.error.HTTPError as exc:
        if optional and exc.code == 404:
            return None
        body = exc.read().decode()
        print(f"ERROR: Vault returned {exc.code} for kv/{path}: {body}", file=sys.stderr)
        sys.exit(1)


# ── Sink ↔ Sesam pipe pairing ────────────────────────────────────────────────────


def load_sink_sesam_map():
    """sink -> Sesam SOURCE dataset (see sink_sesam_map.json). Ignores _comment keys."""
    data = json.loads(SINK_SESAM_MAP.read_text(encoding="utf-8"))
    return {k: v for k, v in data.items() if not k.startswith("_")}


def build_pairs(select_filter):
    """
    Return [{sink, sesam_dataset, source}], one per sink model in models/sinks/.

    sesam_dataset is the Sesam SOURCE dataset feeding the sink's endpoint pipe, taken from
    sink_sesam_map.json — endpoint pipes have sql/rest sinks and are NOT readable (HTTP 503),
    but their source datasets are. Sinks with no mapping (and not in SINKS_WITHOUT_SESAM) are
    returned with sesam_dataset=None and reported as SKIPPED by the caller.
    """
    sink_map = load_sink_sesam_map()
    pairs = []
    for sql in sorted(SINKS_DIR.glob("snk_*.sql")):
        sink = sql.stem
        if select_filter and sink not in select_filter:
            continue
        if sink in SINKS_WITHOUT_SESAM:
            pairs.append({"sink": sink, "sesam_dataset": None, "source": "no-counterpart"})
        elif sink in sink_map:
            pairs.append({"sink": sink, "sesam_dataset": sink_map[sink], "source": "map"})
        else:
            pairs.append({"sink": sink, "sesam_dataset": None, "source": "unmapped"})
    return pairs


def find_compiled_sql(sink):
    """Locate the dbt-compiled SELECT for a sink, or None if not compiled yet."""
    matches = list(DBT_DIR.glob(COMPILED_GLOB.format(sink=sink)))
    return matches[0] if matches else None


# ── RisingWave count ──────────────────────────────────────────────────────────────


def extract_select(compiled_sql):
    """
    Reduce a compiled sink model to just its SELECT, so we can wrap it in COUNT(*).

    Sink models come in two shapes:
      * bare SELECT          (the dbt-risingwave 'sink' materialization wraps it at run time)
      * full CREATE SINK DDL  CREATE SINK ... AS <SELECT ...> WITH (connector=...) [FORMAT ...]
    We strip comments, any leading `CREATE SINK ... AS` header, and the trailing connector
    `WITH (...)` clause. A leading CTE (`WITH cte AS (...)`) is preserved (it has no
    `connector` keyword), and column aliases (`... AS "Id"`) are untouched.
    """
    s = re.sub(r"/\*.*?\*/", "", compiled_sql, flags=re.S)   # block comments
    s = re.sub(r"(?m)--.*$", "", s)                          # line comments
    s = re.sub(r"(?is)^.*?\bCREATE\s+SINK\b.*?\bAS\b\s+", "", s, count=1)  # CREATE SINK header
    s = re.sub(r"(?is)\bWITH\s*\([^)]*\bconnector\b.*$", "", s)            # trailing connector
    return s.strip().rstrip(";").strip()


def get_rw_count(cur, compiled_sql_path, connected_db):
    """
    SELECT COUNT(*) over the sink's compiled SELECT. Returns (count|None, note).
    """
    sql = extract_select(compiled_sql_path.read_text(encoding="utf-8"))
    note = ""
    # Compiled SELECT references a fully-qualified "<db>"."public"."mrt_...". If it was
    # compiled for a different target than we are connected to, the query will fail.
    db_refs = set(re.findall(r'"([^"]+)"\."public"\.', sql))
    other = {d for d in db_refs if d.lower() != (connected_db or "").lower()}
    if other:
        note = f"compiled for db {sorted(other)} != {connected_db}; rerun dbt compile --target"
    try:
        cur.execute(f"SELECT COUNT(*) FROM (\n{sql}\n) AS _sink_count")
        return cur.fetchone()[0], note
    except Exception as exc:
        return None, f"{note + '; ' if note else ''}{exc}".strip()


def extract_from_relation(select_sql):
    """Driving relation after the first FROM (the sink's upstream mart), or None."""
    m = re.search(r'(?is)\bFROM\s+("[^"]+"(?:\s*\.\s*"[^"]+")*|[A-Za-z_]\w*)', select_sql)
    return m.group(1) if m else None


def get_mart_count(cur, compiled_sql_path, connected_db):
    """
    COUNT(*) of the mart the sink reads FROM, WITHOUT the sink's WHERE — i.e. the
    prepared-data layer, the apples-to-apples analog of the Sesam source dataset.
    Returns (count|None, relation|None, note).
    """
    sql = extract_select(compiled_sql_path.read_text(encoding="utf-8"))
    rel = extract_from_relation(sql)
    if not rel:
        return None, None, "could not locate FROM mart"
    try:
        cur.execute(f"SELECT COUNT(*) FROM {rel}")
        return cur.fetchone()[0], rel, ""
    except Exception as exc:
        return None, rel, str(exc)


# ── Sesam count ─────────────────────────────────────────────────────────────────


def sesam_runtime(node_url, token, dataset_id):
    """
    Return the dataset's runtime dict, or -1 (404 / not found), or None (other error).
    """
    base = node_url.rstrip("/")
    if base.endswith("/api"):
        base = base[: -len("/api")]  # SesamBaseUrl may already include /api
    url = f"{base}/api/datasets/{dataset_id}"
    req = urllib.request.Request(
        url, headers={"Authorization": f"bearer {token}", "Accept": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return -1  # dataset / pipe does not exist
        if exc.code == 503:
            return -2  # Sesam node paused/down ("url routing ... doesn't currently work")
        return None
    except Exception:
        return None
    return data.get("runtime", data) or {}


def sesam_nondeleted_count(runtime):
    """
    Non-deleted ("Latest", tombstones excluded) entity count from a Sesam dataset runtime,
    + a flag for whether tombstones were successfully excluded.

    Sesam's index counts are:
      * count-index-exists  — distinct entities in the index INCLUDING those whose latest
                              version is a delete (this is the Sesam UI's "Latest w/ deleted").
      * count-index-deleted — how many of those are tombstones (deleted).
    The "Latest" set we compare against RisingWave is the non-deleted one, i.e.
    count-index-exists - count-index-deleted. (count-index-exists alone over-counts by the
    number of tombstones — e.g. adjustedenergyconsumption-kundeportal: 7715 - 3533 = 4182.)
    """
    if not isinstance(runtime, dict):
        return None, True

    def _num(*keys):
        for k in keys:
            if k in runtime and runtime[k] is not None:
                try:
                    return int(runtime[k])
                except (TypeError, ValueError):
                    pass
        return None

    exists = _num("count-index-exists")
    deleted = _num("count-index-deleted")
    if exists is not None:
        if deleted is not None:
            return exists - deleted, False  # Latest, tombstones excluded
        return exists, True                 # have total but cannot exclude tombstones

    # Fallback for other/older runtime shapes.
    total = _num("entity-count", "entities", "count")
    deleted = _num("deleted-count", "count-index-deleted", "deleted")
    if total is None:
        return None, True
    if deleted is not None:
        return total - deleted, False
    return total, True  # could not exclude tombstones


def sesam_post_filtered_count(node_url, token, dataset_id, not_null_field):
    """
    Count of non-deleted entities in `dataset_id` where `not_null_field` is present —
    for datasets where SESAM_POST_FILTER_NOT_NULL documents a downstream `field != null`
    filter we can't read directly (see that dict's docstring). Fetches entities (heavier
    than the runtime-metadata sesam_nondeleted_count), so only used for the sinks that need it.

    Returns (count|None, status) mirroring sesam_runtime's -1/-2/None convention.
    """
    # Local import: verify_sink_values imports this module at its own top level (for
    # TEST_JSON_DIR/DBT_DIR), so importing it back at our top level would circular-import
    # whenever *this* module isn't the one Python started with (e.g. another script doing
    # `import verify_sink_counts`). Deferring to call time sidesteps that entirely.
    import verify_sink_values as _vv
    rows, status = _vv.fetch_sesam_rows(node_url, token, dataset_id)
    if status is not None:
        if status == 404:
            return -1, None
        if status == 503:
            return -2, None
        return None, None
    return sum(1 for r in rows if r.get(not_null_field) is not None), None


def sesam_dedup_key_count(node_url, token, dataset_id, key_fields):
    """
    Count of DISTINCT `key_fields` tuples among non-deleted entities in `dataset_id` — for
    datasets where SESAM_DEDUP_KEY documents that multiple Sesam entities collapse onto the
    same downstream target primary key (see that dict's docstring). Rows with any null key
    field are excluded (mirrors the sink's own `key_field IS NOT NULL` filters).

    Returns (count|None, status) mirroring sesam_runtime's -1/-2/None convention.
    """
    import verify_sink_values as _vv  # noqa — see sesam_post_filtered_count's import note
    rows, status = _vv.fetch_sesam_rows(node_url, token, dataset_id)
    if status is not None:
        if status == 404:
            return -1, None
        if status == 503:
            return -2, None
        return None, None
    keys = set()
    for r in rows:
        vals = tuple(r.get(f) for f in key_fields)
        if any(v is None for v in vals):
            continue
        keys.add(vals)
    return len(keys), None


# ── Reporting ─────────────────────────────────────────────────────────────────────


def classify(rw_count, sesam_count, tolerance):
    if rw_count is None:
        return "ERROR"
    if sesam_count == -1:
        return "SKIPPED"  # no Sesam dataset (404)
    if sesam_count == -2:
        return "SESAM_DOWN"  # Sesam node paused/down (503)
    if sesam_count is None:
        return "ERROR"
    diff = rw_count - sesam_count
    if diff == 0:
        return "OK"
    if abs(diff) <= tolerance:
        return "WARN"
    return "MISMATCH"


# ── Main ────────────────────────────────────────────────────────────────────────


def main():
    # Windows consoles default to cp1252; force UTF-8 so output never crashes on a symbol.
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:
            pass

    parser = argparse.ArgumentParser(description="Compare sink output counts: RisingWave vs Sesam.")
    parser.add_argument("env", nargs="?", default="test", choices=["dev", "test", "prod"])
    parser.add_argument("--select", help="comma-separated sink names to check (e.g. snk_bygg_forvalter)")
    parser.add_argument("--tolerance", type=int, default=DEFAULT_TOLERANCE,
                        help=f"|RW-Sesam| <= N => WARN not MISMATCH (default {DEFAULT_TOLERANCE})")
    parser.add_argument("--strict", action="store_true", help="exit non-zero on any MISMATCH/ERROR")
    parser.add_argument("--confirm-prod", action="store_true", help="required to target prod")
    parser.add_argument("--json", help="path for the JSON artifact (default verify_sink_counts_<env>.json)")
    parser.add_argument("--csv", help="path for the CSV artifact (default verify_sink_counts_<env>.csv)")
    args = parser.parse_args()
    env = args.env

    # ── Production safety guard ──────────────────────────────────────────────────
    if env == "prod" and not args.confirm_prod:
        print(
            "REFUSING to run against prod without --confirm-prod.\n"
            "  This is read-only, but prod runs require explicit confirmation.",
            file=sys.stderr,
        )
        sys.exit(2)
    if env == "prod":
        print("=" * 70)
        print("  RUNNING AGAINST PRODUCTION (read-only: GET + SELECT COUNT(*) only)")
        print("=" * 70)

    select_filter = None
    if args.select:
        select_filter = {s.strip() for s in args.select.split(",") if s.strip()}

    env_file_map = {
        "dev": REPO_ROOT / ".env.development",
        "test": REPO_ROOT / ".env.test",
        "prod": REPO_ROOT / ".env.production",
    }
    file_env = load_env_file(env_file_map[env])

    def _vopt(key, default=""):
        return file_env.get(key) or os.environ.get(key, default)

    vault_server = _vopt("VaultOptions__Server").rstrip("/")
    vault_token = _vopt("VaultOptions__TokenId")
    if not vault_server or not vault_token:
        print("ERROR: VaultOptions__Server and VaultOptions__TokenId must be set in the env file",
              file=sys.stderr)
        sys.exit(1)

    print(f"==> Environment : {env}")
    print(f"==> Vault       : {vault_server}")
    print("==> Fetching credentials from Vault ...")

    # Sesam creds (kv/kdi/<env>) — note the node URL key is SesamAccessInfo:SesamBaseUrl.
    kdi = vault_read(vault_server, vault_token, f"kdi/{env}")
    sesam_token = kdi.get("SesamAccessInfo:AuthToken", "")
    sesam_url = (
        kdi.get("SesamAccessInfo:SesamBaseUrl")
        or kdi.get("SesamAccessInfo:NodeUrl")
        or kdi.get("SesamAccessInfo:BaseUrl")
        or kdi.get("SesamNodeUrl")
        or ""
    )
    if not sesam_token or not sesam_url:
        print(f"ERROR: Sesam AuthToken / SesamBaseUrl not found in Vault kv/kdi/{env}", file=sys.stderr)
        sys.exit(1)

    # RisingWave creds: prefer kv/Risingwave/<env> (verify_staging_counts.py convention);
    # if the token cannot read it (404), fall back to RisingWaveSettings:* in kv/kdi/<env>.
    rw = vault_read(vault_server, vault_token, f"risingwave/{env}", optional=True)
    if rw and rw.get("DBT_RW_HOST"):
        rw_host = rw.get("DBT_RW_HOST", "")
        rw_user = rw.get("DBT_RW_USER", "root")
        rw_password = rw.get("DBT_RW_PASSWORD", "")
        rw_dbname = rw.get("DBT_RW_DBNAME", env)
        rw_src = f"kv/risingwave/{env}"
    else:
        rw_host = kdi.get("RisingWaveSettings:SqlHost", "")
        rw_user = kdi.get("RisingWaveSettings:SqlUsername", "root")
        rw_password = kdi.get("RisingWaveSettings:SqlPassword", "")
        rw_dbname = env  # matches profiles.yml (dev/test/prod) and the compiled SELECT's db qualifier
        rw_src = f"kv/kdi/{env} RisingWaveSettings"
    if not rw_host:
        print(f"ERROR: no RisingWave host in Vault (neither kv/risingwave/{env} nor "
              f"kv/kdi/{env} RisingWaveSettings:SqlHost)", file=sys.stderr)
        sys.exit(1)
    print(f"==> RW creds   : {rw_src}")

    pairs = build_pairs(select_filter)
    if not pairs:
        print("ERROR: no sinks matched (check --select)", file=sys.stderr)
        sys.exit(1)
    print(f"==> Comparing {len(pairs)} sink <-> Sesam endpoint pairs ...")

    # Connect to RisingWave (read-only).
    try:
        import psycopg2
    except ImportError:
        print("ERROR: psycopg2 not installed — run: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)
    try:
        conn = psycopg2.connect(
            host=rw_host, port=4566, dbname=rw_dbname, user=rw_user, password=rw_password,
            sslmode="require", connect_timeout=15,
        )
    except Exception as exc:
        print(f"ERROR: cannot connect to RisingWave at {rw_host}:4566/{rw_dbname}: {exc}",
              file=sys.stderr)
        sys.exit(1)
    conn.autocommit = True

    print(f"==> RisingWave : {rw_host}:4566/{rw_dbname}")
    print(f"==> Sesam      : {sesam_url}")
    print()

    results = []
    with conn.cursor() as cur:
        for pair in pairs:
            sink, dataset = pair["sink"], pair["sesam_dataset"]
            rw_count, note = None, ""

            skip_extra = {"mart_relation": None, "rw_mart_count": None, "rw_sink_count": None,
                          "sesam_count": None, "diff": None}
            if sink in SINKS_WITHOUT_SESAM:
                results.append({**pair, **skip_extra, "status": "SKIPPED", "note": "no Sesam counterpart"})
                continue
            if dataset is None:
                results.append({**pair, **skip_extra, "status": "SKIPPED", "note": "no Sesam source mapping"})
                continue

            compiled = find_compiled_sql(sink)
            rw_sink = rw_mart = mart_rel = None
            if compiled is None:
                note = "no compiled SELECT — run: dbt compile --select tag:sink --target " + env
            else:
                rw_sink, note = get_rw_count(cur, compiled, rw_dbname)
                rw_mart, mart_rel, mart_note = get_mart_count(cur, compiled, rw_dbname)
                if mart_note:
                    note = "; ".join(n for n in (note, "mart: " + mart_note) if n)

            not_null_field = SESAM_POST_FILTER_NOT_NULL.get(sink)
            dedup_keys = SESAM_DEDUP_KEY.get(sink)
            if not_null_field:
                sesam_count, _ = sesam_post_filtered_count(sesam_url, sesam_token, dataset, not_null_field)
                if sesam_count == -1:
                    sesam_note = "no Sesam dataset (404)"
                elif sesam_count == -2:
                    sesam_note = "Sesam node 503 (paused/down)"
                elif sesam_count is None:
                    sesam_note = "Sesam read error"
                else:
                    sesam_note = f"post-filtered on {not_null_field} != null (downstream -rest pipe)"
            elif dedup_keys:
                sesam_count, _ = sesam_dedup_key_count(sesam_url, sesam_token, dataset, dedup_keys)
                if sesam_count == -1:
                    sesam_note = "no Sesam dataset (404)"
                elif sesam_count == -2:
                    sesam_note = "Sesam node 503 (paused/down)"
                elif sesam_count is None:
                    sesam_note = "Sesam read error"
                else:
                    sesam_note = f"deduped on distinct {'+'.join(dedup_keys)} (target PK)"
            else:
                rt = sesam_runtime(sesam_url, sesam_token, dataset)
                if rt == -1:
                    sesam_count, sesam_note = -1, "no Sesam dataset (404)"
                elif rt == -2:
                    sesam_count, sesam_note = -2, "Sesam node 503 (paused/down)"
                elif rt is None:
                    sesam_count, sesam_note = None, "Sesam read error"
                else:
                    sesam_count, includes_deleted = sesam_nondeleted_count(rt)
                    sesam_note = "incl. tombstones?" if includes_deleted and sesam_count is not None else ""

            # Status: compare Sesam against whichever RW layer is CLOSER — the prepared mart
            # (rw_mart) or the post-WHERE/dedup sink output (rw_sink) — and call it OK if EITHER
            # matches (within tolerance). A real sink filter (e.g. faktura's elektronisk=1) makes
            # rw_sink < rw_mart; a row-expanding join makes rw_sink > rw_mart. Comparing the closer
            # layer avoids a false MISMATCH in both cases, yet still flags gaps where NEITHER matches.
            rw_candidates = [c for c in (rw_mart, rw_sink) if c is not None]
            layer_note = ""
            if isinstance(sesam_count, int) and sesam_count >= 0 and rw_candidates:
                best = min(rw_candidates, key=lambda c: abs(c - sesam_count))
                status = classify(best, sesam_count, args.tolerance)
                diff = best - sesam_count
                if rw_mart is not None and rw_sink is not None and rw_mart != rw_sink:
                    layer_note = "rw_sink matches" if best == rw_sink else "rw_mart matches"
            else:
                primary = rw_mart if rw_mart is not None else rw_sink
                status = classify(primary, sesam_count, args.tolerance)
                diff = None
            results.append({
                "sink": sink, "sesam_dataset": dataset, "source": pair["source"],
                "mart_relation": mart_rel, "rw_mart_count": rw_mart, "rw_sink_count": rw_sink,
                "sesam_count": (None if sesam_count in (-1, -2, None) else sesam_count),
                "diff": diff, "status": status,
                "note": "; ".join(n for n in (note, sesam_note, layer_note) if n),
            })
    conn.close()

    # ── Print table ──────────────────────────────────────────────────────────────
    col_sink = max([len(r["sink"]) for r in results] + [4]) + 1
    col_ds = max([len(r["sesam_dataset"] or "-") for r in results] + [19]) + 1
    header = (f"  {'Sink':<{col_sink}}  {'Sesam source dataset':<{col_ds}}  "
              f"{'RW mart':>8}  {'RW sink':>8}  {'Sesam':>8}  {'Diff':>7}  Status")
    print(header)
    print("  " + "-" * (len(header) - 2))

    def _s(v):
        return "-" if v is None else str(v)

    counts = {k: 0 for k in ("OK", "WARN", "MISMATCH", "SKIPPED", "SESAM_DOWN", "ERROR")}
    for r in results:
        counts[r["status"]] += 1
        diff_str = "" if r["diff"] is None else (f"{r['diff']:+d}" if r["diff"] else "0")
        line = (f"  {r['sink']:<{col_sink}}  {(r['sesam_dataset'] or '-'):<{col_ds}}  "
                f"{_s(r['rw_mart_count']):>8}  {_s(r['rw_sink_count']):>8}  {_s(r['sesam_count']):>8}  "
                f"{diff_str:>7}  {r['status']}")
        if r["note"]:
            line += f"  ({r['note']})"
        print(line)

    print()
    print(f"  Summary: {len(results)} pairs | " + " | ".join(
        f"{counts[k]} {k}" for k in ("OK", "WARN", "MISMATCH", "SKIPPED", "SESAM_DOWN", "ERROR")))
    print()

    # ── JSON artifact ──────────────────────────────────────────────────────────────
    artifact = {
        "env": env,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "tolerance": args.tolerance,
        "summary": {"pairs": len(results), **{k.lower(): v for k, v in counts.items()}},
        "results": results,
    }
    out_path = Path(args.json) if args.json else (DBT_DIR / f"verify_sink_counts_{env}.json")
    out_path.write_text(json.dumps(artifact, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"==> Wrote {out_path}")

    # ── CSV artifact (one row per sink, sorted by magnitude of divergence) ──────────
    # Sorted by abs_diff DESCENDING so the largest divergences sit at the top regardless
    # of sign. 'diff' keeps its sign (- = RW has FEWER than Sesam, + = RW has MORE);
    # 'abs_diff' is the magnitude the rows are sorted on (so -66351 ranks above -674).
    # Rows with no numeric diff (SKIPPED / not-compiled) sort to the bottom. A
    # 'criticality' column is kept so you can re-sort by status in a spreadsheet.
    CSV_RANK = {"OK": 0, "MISMATCH": 1, "WARN": 2, "ERROR": 3, "SESAM_DOWN": 4, "SKIPPED": 5}

    def _csv_key(r):
        gap = abs(r["diff"]) if isinstance(r["diff"], int) else -1  # no numeric diff → bottom
        return (-gap, CSV_RANK.get(r["status"], 9), r["sink"])

    csv_path = Path(args.csv) if args.csv else (DBT_DIR / f"verify_sink_counts_{env}.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter=";")
        writer.writerow(["criticality", "sink", "status", "sesam_dataset", "source",
                         "rw_mart", "rw_sink", "sesam", "diff", "abs_diff", "mart_relation", "note"])
        for r in sorted(results, key=_csv_key):
            abs_diff = abs(r["diff"]) if isinstance(r["diff"], int) else ""
            writer.writerow([
                CSV_RANK.get(r["status"], 9), r["sink"], r["status"],
                r["sesam_dataset"] or "", r["source"] or "",
                _s(r["rw_mart_count"]), _s(r["rw_sink_count"]), _s(r["sesam_count"]),
                ("" if r["diff"] is None else r["diff"]), abs_diff,
                r["mart_relation"] or "", r["note"],
            ])
    print(f"==> Wrote {csv_path}")

    if args.strict and (counts["MISMATCH"] or counts["ERROR"]):
        sys.exit(1)


if __name__ == "__main__":
    main()
