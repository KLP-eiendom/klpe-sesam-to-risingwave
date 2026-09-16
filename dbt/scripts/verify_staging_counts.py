#!/usr/bin/env python3
"""
verify_staging_counts.py — Compare poller staging table row counts between
RisingWave and the corresponding Sesam environment.

Usage (run from the dbt/ directory):
    python scripts/verify_staging_counts.py [env]

    env defaults to 'dev'. Options: dev | test | prod

Vault secrets fetched:
  kv/Risingwave/<env>  →  DBT_RW_HOST, DBT_RW_USER, DBT_RW_PASSWORD, DBT_RW_DBNAME
  kv/kdi/<env>         →  SesamAccessInfo:AuthToken, SesamAccessInfo:NodeUrl

Sesam dataset name is derived from the RisingWave table name:
    stg_d365_ansatt  →  d365-ansatt   (remove 'stg_' prefix, replace '_' with '-')

Requires: pip install psycopg2-binary
"""

import json
import os
import ssl
import sys
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
DBT_DIR = SCRIPT_DIR.parent
REPO_ROOT = DBT_DIR.parent

# ── Overrides for tables where auto-derived Sesam dataset name differs ────────

# Format: RisingWave table name → Sesam dataset id
SESAM_DATASET_OVERRIDES = {
    # Eiendom poller fetches forvalter/prosjekt/process children; Sesam source is forvalter
    "stg_eiendom_prosjektsortedusertask": "forvalter-prosjektsortedusertask",
}

# Tables where a count difference is structurally expected (children expanded from parents)
CHILDREN_TABLES = {
    "stg_eiendom_prosjektsortedusertask",
}

# ── Vault helpers ─────────────────────────────────────────────────────────────

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


def vault_read(server, token, path):
    url = f"{server}/v1/kv/{path}"
    req = urllib.request.Request(url, headers={"X-Vault-Token": token})
    try:
        with urllib.request.urlopen(req, context=_ssl_ctx()) as resp:
            return json.loads(resp.read()).get("data", {})
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()
        print(f"ERROR: Vault returned {exc.code} for kv/{path}: {body}", file=sys.stderr)
        sys.exit(1)


# ── Table list from poller appsettings ───────────────────────────────────────

def build_poller_tables():
    """Return list of (target_table, poller_name) from all appsettings.json files."""
    pollers = [
        (
            REPO_ROOT / "src/cloud-run/bigquery-entity-poller/appsettings.json",
            "bigquery",
            lambda d: d.get("BigQuerySettings", {}).get("Tables", []),
        ),
        (
            REPO_ROOT / "src/cloud-run/superoffice-entity-poller/appsettings.json",
            "superoffice",
            lambda d: d.get("KdiApiSettings", {}).get("Entities", []),
        ),
        (
            REPO_ROOT / "src/cloud-run/fdvweb-entity-poller/appsettings.json",
            "fdvweb",
            lambda d: d.get("FdvwebApiSettings", {}).get("Entities", []),
        ),
        (
            REPO_ROOT / "src/cloud-run/eiendom-entity-poller/appsettings.json",
            "eiendom",
            lambda d: d.get("EiendomApiSettings", {}).get("Entities", []),
        ),
    ]
    rows = []
    seen = set()
    for path, poller, extractor in pollers:
        try:
            d = json.loads(Path(path).read_text(encoding="utf-8"))
            for entry in extractor(d):
                tbl = entry.get("TargetTable", "")
                if tbl and tbl not in seen:
                    rows.append((tbl, poller))
                    seen.add(tbl)
        except Exception as exc:
            print(f"WARN: Could not read {path}: {exc}", file=sys.stderr)
    return rows


# ── RisingWave queries ────────────────────────────────────────────────────────

def get_rw_counts(host, port, dbname, user, password, schema, tables):
    """Return {table: count_or_None} for each table name in tables."""
    try:
        import psycopg2
    except ImportError:
        print("ERROR: psycopg2 not installed — run: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)

    counts = {}
    try:
        conn = psycopg2.connect(
            host=host,
            port=int(port),
            dbname=dbname,
            user=user,
            password=password,
            sslmode="require",
            connect_timeout=15,
        )
    except Exception as exc:
        print(f"ERROR: Cannot connect to RisingWave at {host}:{port}/{dbname}: {exc}", file=sys.stderr)
        sys.exit(1)

    conn.autocommit = True
    with conn.cursor() as cur:
        for table in tables:
            try:
                cur.execute(f'SELECT COUNT(*) FROM "{schema}"."{table}"')
                counts[table] = cur.fetchone()[0]
            except Exception as exc:
                counts[table] = None
    conn.close()
    return counts


# ── Sesam API ─────────────────────────────────────────────────────────────────

def sesam_dataset_count(node_url, token, dataset_id):
    """
    Return entity count (int) for a Sesam dataset.
    Returns -1 if the dataset is not found (404).
    Returns None on other errors.
    """
    url = f"{node_url.rstrip('/')}/api/datasets/{dataset_id}"
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"bearer {token}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        return -1 if exc.code == 404 else None
    except Exception:
        return None

    # Sesam returns entity-count in dataset['runtime']['entity-count']
    runtime = data.get("runtime", {})
    for key in ("entity-count", "entities", "count"):
        if key in runtime:
            return int(runtime[key])
    # Fallback: some Sesam versions expose count at top level
    for key in ("entity-count", "count"):
        if key in data:
            return int(data[key])
    return None


def table_to_sesam_dataset(table_name):
    """stg_d365_ansatt → d365-ansatt"""
    if table_name in SESAM_DATASET_OVERRIDES:
        return SESAM_DATASET_OVERRIDES[table_name]
    prefix = "stg_"
    name = table_name[len(prefix):] if table_name.startswith(prefix) else table_name
    return name.replace("_", "-")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    env = sys.argv[1] if len(sys.argv) > 1 else "dev"

    env_file_map = {
        "dev":  REPO_ROOT / ".env.development",
        "test": REPO_ROOT / ".env.test",
        "prod": REPO_ROOT / ".env.production",
    }
    if env not in env_file_map:
        print(f"ERROR: Unknown environment '{env}'. Use: dev | test | prod", file=sys.stderr)
        sys.exit(1)

    env_file = env_file_map[env]
    file_env = load_env_file(env_file)

    def _vopt(key, default=""):
        return file_env.get(key) or os.environ.get(key, default)

    vault_server = _vopt("VaultOptions__Server").rstrip("/")
    vault_token  = _vopt("VaultOptions__TokenId")

    if not vault_server or not vault_token:
        print(
            "ERROR: VaultOptions__Server and VaultOptions__TokenId must be set in env file or environment",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"==> Environment : {env}")
    print(f"==> Vault       : {vault_server}")
    print()
    print("==> Fetching RisingWave credentials ...")
    rw = vault_read(vault_server, vault_token, f"risingwave/{env}")
    rw_host     = rw.get("DBT_RW_HOST", "")
    rw_user     = rw.get("DBT_RW_USER", "risingwave")
    rw_password = rw.get("DBT_RW_PASSWORD", "")
    rw_dbname   = rw.get("DBT_RW_DBNAME", env)

    if not rw_host or rw_host == "localhost":
        print(
            "WARN: DBT_RW_HOST is 'localhost' — ensure kubectl port-forward is active on :4566",
            file=sys.stderr,
        )

    print("==> Fetching Sesam credentials ...")
    kdi = vault_read(vault_server, vault_token, f"kdi/{env}")
    sesam_token = kdi.get("SesamAccessInfo:AuthToken", "")
    sesam_url   = (
        kdi.get("SesamAccessInfo:SesamBaseUrl")
        or kdi.get("SesamAccessInfo:NodeUrl")
        or kdi.get("SesamAccessInfo:BaseUrl")
        or kdi.get("SesamNodeUrl")
        or ""
    )

    if not sesam_token:
        print(
            f"ERROR: SesamAccessInfo:AuthToken not found in Vault kv/kdi/{env}",
            file=sys.stderr,
        )
        sys.exit(1)
    if not sesam_url:
        sesam_keys = [k for k in sorted(kdi) if "sesam" in k.lower() or "node" in k.lower()]
        print(
            f"ERROR: Sesam node URL not found in Vault kv/kdi/{env}.\n"
            f"  Tried keys: SesamAccessInfo:NodeUrl, SesamAccessInfo:BaseUrl, SesamNodeUrl\n"
            f"  Available Sesam/node keys: {sesam_keys or '(none)'}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Build table list
    poller_tables = build_poller_tables()
    table_names = [t for t, _ in poller_tables]
    table_poller = {t: p for t, p in poller_tables}
    print(f"==> Found {len(table_names)} poller staging tables")

    # Query RisingWave
    print(f"==> Querying RisingWave ({rw_host}:{4566}/{rw_dbname}) ...")
    rw_counts = get_rw_counts(rw_host, 4566, rw_dbname, rw_user, rw_password, "public", table_names)

    # Query Sesam and print report
    print(f"==> Querying Sesam ({sesam_url}) ...")
    print()

    col_tbl = max(len(t) for t in table_names) + 1
    col_ds  = max(len(table_to_sesam_dataset(t)) for t in table_names) + 1

    header = f"  {'Table':<{col_tbl}}  {'Sesam dataset':<{col_ds}}  {'RW':>9}  {'Sesam':>9}  {'Diff':>8}  Status"
    print(header)
    print("  " + "-" * (len(header) - 2))

    ok = mismatch = not_found = errors = 0

    for table in sorted(table_names):
        dataset    = table_to_sesam_dataset(table)
        rw_count   = rw_counts.get(table)
        sesam_count = sesam_dataset_count(sesam_url, sesam_token, dataset)

        if rw_count is None:
            status = "ERROR (RW)"
            rw_str = "ERR"
            sesam_str = str(sesam_count) if sesam_count not in (None, -1) else "?"
            diff_str = ""
            errors += 1
        elif sesam_count == -1:
            status = "NOT IN SESAM"
            rw_str = str(rw_count)
            sesam_str = "—"
            diff_str = ""
            not_found += 1
        elif sesam_count is None:
            status = "ERROR (Sesam)"
            rw_str = str(rw_count)
            sesam_str = "ERR"
            diff_str = ""
            errors += 1
        else:
            diff = rw_count - sesam_count
            rw_str    = str(rw_count)
            sesam_str = str(sesam_count)
            diff_str  = f"{diff:+d}" if diff != 0 else "0"
            if diff == 0:
                status = "OK"
                ok += 1
            elif table in CHILDREN_TABLES:
                status = "OK (expanded children)"
                ok += 1
            else:
                status = "MISMATCH"
                mismatch += 1

        print(
            f"  {table:<{col_tbl}}  {dataset:<{col_ds}}  {rw_str:>9}  {sesam_str:>9}  {diff_str:>8}  {status}"
        )

    print()
    print(
        f"  Summary: {len(table_names)} tables | "
        f"{ok} OK | {mismatch} MISMATCH | {not_found} not in Sesam | {errors} errors"
    )
    print()

    if mismatch > 0 or errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
