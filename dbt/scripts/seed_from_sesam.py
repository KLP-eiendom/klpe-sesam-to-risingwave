#!/usr/bin/env python3
"""
seed_from_sesam.py — populate RisingWave staging (stg_*) tables from Sesam *source* datasets.

RisingWave's live streaming/pollers are currently unreliable, but the Sesam→RisingWave migration
must keep moving. This tool reads a Sesam source dataset (the input data, namespaced) and writes
the rows straight into the corresponding RW stg_* table, bypassing the poller. RisingWave's
streaming then propagates the seeded rows downstream into marts and sinks automatically.

READ ↔ WRITE wiring (independent envs, guard enforced before any connection):
    --sesam-env  reads  Vault kdi/<env>        (SesamAccessInfo:SesamBaseUrl + :AuthToken)
    --rw-env     writes Vault risingwave/<env>  (owner DBT_RW_USER → full INSERT/DELETE)
  The ONLY forbidden case is writing PROD from a non-prod source (rw-env=prod requires
  sesam-env=prod). prod→test/dev is allowed (no sensitive data). Any prod write needs --confirm-prod.

Two table shapes, both written via SQL DML (RW accepts INSERT/DELETE on webhook-connector tables):
  • poller table — flat columns; case-insensitive match of Sesam fields to the stg DDL columns.
  • webhook table — single `payload JSONB`; the whole (cleaned) Sesam entity becomes the payload.

Priority registry: scripts/seed_targets.json — one boolean per seedable stg table.
  true  = already has data / seeding done  → PROMPT before re-seeding (avoid clobbering)
  false = empty / not yet seeded           → priority target, seeds without prompt
Generate/refresh with --init-config (live COUNT(*) on the rw-env); tweak by hand thereafter.

Usage (run from dbt/):
    python scripts/seed_from_sesam.py --sesam-env test --rw-env test --select stg_superoffice_user --dry-run
    python scripts/seed_from_sesam.py --sesam-env test --rw-env test --select stg_superoffice_user
    python scripts/seed_from_sesam.py --sesam-env test --rw-env test --all
    python scripts/seed_from_sesam.py --init-config --rw-env test

Reuses (does NOT modify): verify_sink_counts (load_env_file/vault_read), verify_sink_values
(sesam_get_page/fetch_sesam_rows/strip_prefix), verify_staging_counts (table_to_sesam_dataset),
load_test_data (get_table_columns/is_webhook_table/is_cdc_table). seed_overrides for per-table tweaks.
"""

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
DBT_DIR = SCRIPT_DIR.parent
REPO_ROOT = DBT_DIR.parent
STAGING_DIR = DBT_DIR / "models" / "staging"
TARGETS_PATH = SCRIPT_DIR / "seed_targets.json"

sys.path.insert(0, str(SCRIPT_DIR))
import verify_sink_counts as vc          # noqa: E402  load_env_file, vault_read
import verify_sink_values as vv          # noqa: E402  sesam_get_page, fetch_sesam_rows, strip_prefix
import verify_staging_counts as vs       # noqa: E402  table_to_sesam_dataset, SESAM_DATASET_OVERRIDES
import load_test_data as ltd             # noqa: E402  get_table_columns, is_webhook_table, is_cdc_table
import seed_overrides as ov              # noqa: E402  SEED_OVERRIDES, evaluate

ENVS = ("dev", "test", "prod")
ENV_FILE = {
    "dev": REPO_ROOT / ".env.development",
    "test": REPO_ROOT / ".env.test",
    "prod": REPO_ROOT / ".env.production",
}
SCHEMA = "public"


# ── env guard ──────────────────────────────────────────────────────────────────

def enforce_guard(sesam_env, rw_env, confirm_prod):
    for name, val in (("--sesam-env", sesam_env), ("--rw-env", rw_env)):
        if val not in ENVS:
            sys.exit(f"ERROR: {name} must be one of {ENVS} (got {val!r})")
    if rw_env == "prod":
        if sesam_env != "prod":
            sys.exit("REFUSED: writing prod from a non-prod source. "
                     "--rw-env prod requires --sesam-env prod.")
        if not confirm_prod:
            sys.exit("REFUSED: --rw-env prod requires --confirm-prod.")
    # every other pairing (incl. prod→test/dev) is allowed — DBs hold no sensitive data.


# ── credentials ──────────────────────────────────────────────────────────────────

def _vault(env):
    fe = vc.load_env_file(ENV_FILE[env])
    server = (fe.get("VaultOptions__Server") or "").rstrip("/")
    token = fe.get("VaultOptions__TokenId") or ""
    if not server or not token:
        sys.exit(f"ERROR: VaultOptions__Server / __TokenId missing in {ENV_FILE[env].name}")
    return server, token


def sesam_creds(sesam_env):
    server, token = _vault(sesam_env)
    kdi = vc.vault_read(server, token, f"kdi/{sesam_env}")
    base = (kdi.get("SesamAccessInfo:SesamBaseUrl") or kdi.get("SesamAccessInfo:NodeUrl")
            or kdi.get("SesamAccessInfo:BaseUrl") or "")
    auth = kdi.get("SesamAccessInfo:AuthToken", "")
    if not base or not auth:
        sys.exit(f"ERROR: Sesam BaseUrl/AuthToken not in Vault kdi/{sesam_env}")
    return base.rstrip("/"), auth


def rw_creds(rw_env):
    server, token = _vault(rw_env)
    rw = vc.vault_read(server, token, f"risingwave/{rw_env}")
    host = rw.get("DBT_RW_HOST", "")
    if not host:
        sys.exit(f"ERROR: DBT_RW_HOST not in Vault risingwave/{rw_env}")
    return {
        "host": host,
        "port": int(rw.get("DBT_RW_PORT", "4566")),
        "user": rw.get("DBT_RW_USER", "root"),
        "password": rw.get("DBT_RW_PASSWORD", ""),
        "dbname": rw.get("DBT_RW_DBNAME", rw_env),
    }


def rw_connect(c):
    try:
        import psycopg2
    except ImportError:
        sys.exit("ERROR: psycopg2 not installed — pip install psycopg2-binary")
    conn = psycopg2.connect(host=c["host"], port=c["port"], dbname=c["dbname"],
                            user=c["user"], password=c["password"],
                            sslmode="require", connect_timeout=20)
    conn.autocommit = True
    return conn


# ── pipe discovery / classification ───────────────────────────────────────────────

def discover_tables():
    """All seedable stg tables → 'webhook' | 'poller'.

    Excluded (no Sesam source dataset to seed from): CDC tables (reference a source via
    `FROM {{ ref('src_..._cdc') }}`, or render `WHERE FALSE` in localdev) and derived staging
    MVs that select from another model (`FROM {{ ref('stg_...') }}`). Poller/webhook tables have
    no FROM — the poller/HTTP push inserts into them."""
    out = {}
    for sql in sorted(STAGING_DIR.glob("stg_*.sql")):
        t = sql.stem
        if ltd.is_webhook_table(t):          # single payload JSONB, no FROM
            out[t] = "webhook"
            continue
        low = sql.read_text(encoding="utf-8").lower()
        if "from {{ ref(" in low or "from {{ref(" in low or "where false" in low:
            continue                          # CDC or derived-from-another-model → not seedable
        out[t] = "poller"
    return out


def sesam_dataset_for(table):
    return ov.get_override(table).get("sesam_dataset") or vs.table_to_sesam_dataset(table)


# ── seed_targets.json registry ─────────────────────────────────────────────────────

def load_targets():
    if TARGETS_PATH.exists():
        return json.loads(TARGETS_PATH.read_text(encoding="utf-8"))
    return {}


def save_targets(d):
    TARGETS_PATH.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def init_config(rw_env):
    """(Re)generate seed_targets.json: true if the stg table currently has rows in rw-env."""
    tables = discover_tables()
    conn = rw_connect(rw_creds(rw_env))
    existing = load_targets()
    out = {}
    with conn.cursor() as cur:
        for t in sorted(tables):
            try:
                cur.execute(f'SELECT COUNT(*) FROM "{SCHEMA}"."{t}"')
                n = cur.fetchone()[0]
            except Exception:
                n = None
            # preserve a hand-set true; otherwise has_data = count>0
            out[t] = bool(existing.get(t)) or (n is not None and n > 0)
            print(f"  {t:48s} {tables[t]:8s} rows={'-' if n is None else n:>8}  -> {out[t]}")
    conn.close()
    save_targets(out)
    n_false = sum(1 for v in out.values() if not v)
    print(f"\nWrote {TARGETS_PATH.relative_to(REPO_ROOT)} — {len(out)} tables, "
          f"{n_false} empty (priority) / {len(out) - n_false} with data.")


# ── transform ──────────────────────────────────────────────────────────────────

def clean_scalar(v):
    """Strip Sesam transit prefixes: ~f -> float; ~t/~:/~u/~r -> bare string; else passthrough."""
    if isinstance(v, str) and len(v) >= 2 and v[0] == "~":
        if v[1] == "f":
            try:
                return float(v[2:])
            except ValueError:
                return v
        return v[2:]
    return v


def clean_deep(obj):
    if isinstance(obj, dict):
        return {k: clean_deep(x) for k, x in obj.items()}
    if isinstance(obj, list):
        return [clean_deep(x) for x in obj]
    return clean_scalar(obj)


def deep_strip_keys(obj):
    """Recursively strip a single leading '<ns>:' from EVERY dict key. Sesam namespaces nested
    object keys too (e.g. owners[].'verified-envelope:email'), but strip_prefix/fetch_sesam_rows
    only clean the top level. The production webhook delivers clean keys, so marts read e.g.
    own->>'email' — nested namespaces would make those NULL. Leaves '_*' and 'rdf:*' untouched."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            nk = k if (k.startswith("_") or k.startswith("rdf:")) else (k.split(":", 1)[1] if ":" in k else k)
            out.setdefault(nk, deep_strip_keys(v))
        return out
    if isinstance(obj, list):
        return [deep_strip_keys(x) for x in obj]
    return obj


def transform_rows(rows, table):
    """Apply field_renames + computed_fields + computed _id to strip-prefixed Sesam rows
    (deep-clean stays per-shape)."""
    ovr = ov.get_override(table)
    renames = ovr.get("field_renames") or {}
    computed = ovr.get("computed_fields") or {}
    id_expr = ovr.get("id")
    where = ovr.get("where_filter")
    out = []
    for r in rows:
        r = deep_strip_keys(r)          # clean namespaces at ALL levels (nested arrays/objects)
        if where and not where(r):
            continue
        if renames:
            r = {renames.get(k, k): v for k, v in r.items()}
        if computed:
            r = dict(r)
            for col, fn in computed.items():
                r[col] = fn(r)
        if id_expr:
            r = dict(r)
            r["_id"] = ov.evaluate(id_expr, r)
        out.append(r)
    return out


# ── write ──────────────────────────────────────────────────────────────────────

def clear_table(cur, table):
    cur.execute(f'DELETE FROM "{SCHEMA}"."{table}"')


def write_poller(conn, table, rows, batch):
    from psycopg2.extras import execute_values
    with conn.cursor() as cur:
        table_cols = ltd.get_table_columns(conn, table)
        if not table_cols:
            print(f"  [{table}] ERROR: table not found / no columns — skipped", file=sys.stderr)
            return 0
        lower = {c.lower(): c for c in table_cols}
        json_keys = list(dict.fromkeys(k for r in rows for k in r.keys()))
        db_to_json = {lower[k.lower()]: k for k in json_keys if k.lower() in lower}
        if "_id" not in {c.lower() for c in db_to_json}:
            print(f"  [{table}] ERROR: no _id column matched — skipped", file=sys.stderr)
            return 0
        dropped = [k for k in json_keys if k.lower() not in lower]
        if dropped:
            print(f"  [{table}] note: Sesam fields not in stg DDL (dropped): {dropped}")
        cols = list(db_to_json.keys())

        def cell(v):
            v = clean_scalar(v)
            return json.dumps(v) if isinstance(v, (dict, list)) else v

        data = [tuple(cell(r.get(db_to_json[c])) for c in cols) for r in rows]
        clear_table(cur, table)
        col_sql = ", ".join(f'"{c}"' for c in cols)
        tmpl = "(" + ", ".join(["%s"] * len(cols)) + ")"
        execute_values(cur, f'INSERT INTO "{SCHEMA}"."{table}" ({col_sql}) VALUES %s',
                       data, template=tmpl, page_size=batch)
    return len(rows)


def write_webhook(conn, table, rows, batch):
    """Insert cleaned entities as `payload`. Most webhook tables have only that one column,
    but some (e.g. stg_superoffice_user) also declare a typed PK/extra column matching a
    top-level payload key (e.g. "personId") — extract it from the same cleaned entity so
    the column isn't left NULL (which would violate a PRIMARY KEY on a multi-column table)."""
    from psycopg2.extras import execute_values
    table_cols = ltd.get_table_columns(conn, table)
    extra_cols = sorted(c for c in table_cols if c.lower() != "payload")
    cleaned = [clean_deep(r) for r in rows]

    if not extra_cols:
        # unchanged from before: single payload column, no extraction
        data = [(json.dumps(entity, ensure_ascii=False),) for entity in cleaned]
        with conn.cursor() as cur:
            clear_table(cur, table)
            execute_values(cur, f'INSERT INTO "{SCHEMA}"."{table}" (payload) VALUES %s',
                           data, template="(%s::jsonb)", page_size=batch)
        return len(rows)

    # Validate BEFORE clear_table/INSERT: an entity missing a value for an extra column would
    # otherwise flow through as NULL and only fail later at INSERT time (raw psycopg2 NOT-NULL/PK
    # error) — by then clear_table has already run (autocommit), leaving the table empty with no
    # indication of which entities were bad. Fail fast instead, naming the table/column(s)/count.
    bad = []
    bad_cols = set()
    for entity in cleaned:
        missing = [c for c in extra_cols if entity.get(c) is None]
        if missing:
            bad.append(entity)
            bad_cols.update(missing)
    if bad:
        cols = ", ".join(sorted(bad_cols))
        samples = [
            str(entity["_id"]) if entity.get("_id") is not None else repr(entity)[:150]
            for entity in bad[:3]
        ]
        raise ValueError(
            f"[{table}] ERROR: {len(bad)} entit{'y' if len(bad) == 1 else 'ies'} missing required "
            f"column(s) [{cols}] (entity.get() returned None) — would insert NULL into a "
            f"NOT NULL/PK column. Aborting before clear_table/INSERT — table left untouched. "
            f"Sample entities: {samples}"
        )

    col_sql = ", ".join(['"payload"'] + [f'"{c}"' for c in extra_cols])
    tmpl = "(%s::jsonb" + ", %s" * len(extra_cols) + ")"
    data = [
        tuple([json.dumps(entity, ensure_ascii=False)] + [entity.get(c) for c in extra_cols])
        for entity in cleaned
    ]
    with conn.cursor() as cur:
        clear_table(cur, table)
        execute_values(cur, f'INSERT INTO "{SCHEMA}"."{table}" ({col_sql}) VALUES %s',
                       data, template=tmpl, page_size=batch)
    return len(rows)


# ── orchestration ──────────────────────────────────────────────────────────────

def resolve_selection(args, tables, targets):
    if args.select:
        wanted = [s.strip() for s in args.select.split(",") if s.strip()]
        unknown = [t for t in wanted if t not in tables]
        if unknown:
            sys.exit(f"ERROR: not seedable stg tables: {unknown}")
        return wanted
    if args.all:
        # priority: empty (false) first; stable name order within
        return [t for t in sorted(tables) if not targets.get(t)]
    sys.exit("ERROR: pass --select <tables> or --all")


def confirm_reseed(table):
    try:
        ans = input(f"  [{table}] marked working/has-data in seed_targets.json — re-seed anyway? [y/N] ")
    except EOFError:
        ans = ""
    return ans.strip().lower() in ("y", "yes")


def main():
    ap = argparse.ArgumentParser(description="Seed RisingWave stg_* tables from Sesam source datasets.")
    ap.add_argument("--sesam-env", choices=ENVS, help="Sesam source env (Vault kdi/<env>)")
    ap.add_argument("--rw-env", choices=ENVS, required=True, help="RisingWave target env (Vault risingwave/<env>)")
    ap.add_argument("--select", help="comma-separated stg tables")
    ap.add_argument("--all", action="store_true", help="seed all 'false' (empty/priority) entries, empty-first")
    ap.add_argument("--init-config", action="store_true", help="(re)generate seed_targets.json from rw-env counts")
    ap.add_argument("--mark-done", action="store_true", help="flip successfully-seeded tables to true in seed_targets.json")
    ap.add_argument("--force", "--yes", dest="force", action="store_true", help="seed 'true' tables without prompting")
    ap.add_argument("--max-rows", type=int, default=0, help="per-table cap (0 = full)")
    ap.add_argument("--page-limit", type=int, default=1000)
    ap.add_argument("--batch", type=int, default=1000)
    ap.add_argument("--dry-run", action="store_true", help="fetch+transform+report only; no writes")
    ap.add_argument("--confirm-prod", action="store_true")
    args = ap.parse_args()

    if args.init_config:
        print(f"==> --init-config from rw-env={args.rw_env}")
        init_config(args.rw_env)
        return

    if not args.sesam_env:
        sys.exit("ERROR: --sesam-env is required (unless --init-config)")
    enforce_guard(args.sesam_env, args.rw_env, args.confirm_prod)

    tables = discover_tables()
    targets = load_targets()
    selection = resolve_selection(args, tables, targets)

    base, sauth = sesam_creds(args.sesam_env)
    print(f"==> Sesam  : {base}  (env {args.sesam_env})")
    print(f"==> RW     : {args.rw_env}{' [WRITE]' if not args.dry_run else ' [dry-run, no writes]'}")
    print(f"==> Tables : {len(selection)} selected\n")

    seeded_ok = []
    for table in selection:
        kind = tables[table]
        dataset = sesam_dataset_for(table)

        if not args.dry_run and targets.get(table) and not args.force:
            if not confirm_reseed(table):
                print(f"  [{table}] skipped (kept).")
                continue

        cap = args.max_rows if args.max_rows > 0 else 300000
        rows, status = vv.fetch_sesam_rows(base, sauth, dataset, page_limit=args.page_limit, hard_cap=cap)
        if status is not None:
            print(f"  [{table}] SESAM {dataset}: error {status} — skipped", file=sys.stderr)
            continue
        rows = transform_rows(rows, table)
        if args.max_rows > 0:
            rows = rows[:args.max_rows]

        if args.dry_run:
            sample = rows[0] if rows else {}
            print(f"  [{table}] {kind:7s} <- {dataset}: {len(rows)} rows  "
                  f"(sample keys: {sorted(list(sample.keys()))[:8]})")
            continue

        try:
            conn = rw_connect(rw_creds(args.rw_env))
            try:
                if kind == "webhook":
                    n = write_webhook(conn, table, rows, args.batch)
                else:
                    n = write_poller(conn, table, rows, args.batch)
                print(f"  [{table}] {kind:7s} <- {dataset}: cleared + inserted {n} rows")
                if n:
                    seeded_ok.append(table)
            finally:
                conn.close()
        except Exception as exc:
            print(f"  [{table}] WRITE ERROR: {exc}", file=sys.stderr)

    if args.mark_done and seeded_ok and not args.dry_run:
        targets.update({t: True for t in seeded_ok})
        save_targets(targets)
        print(f"\n--mark-done: set {len(seeded_ok)} table(s) true in {TARGETS_PATH.name}")

    print("\nDone." + ("" if args.dry_run else " RisingWave streaming will propagate downstream."))


if __name__ == "__main__":
    main()
