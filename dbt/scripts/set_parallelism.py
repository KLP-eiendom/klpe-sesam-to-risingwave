#!/usr/bin/env python3
"""
set_parallelism.py — Sweep existing RisingWave streaming jobs (sources, tables,
materialized views, sinks) down to an explicit low parallelism, WITHOUT a
full-refresh/backfill.

Why: RisingWave's default parallelism for a streaming job is adaptive — it
scales with the cluster's current compute capacity (see
dbt/dbt_project.yml's `+pre-hook: SET streaming_parallelism = 1`, which fixes
this for models deployed/full-refreshed going forward). Scaling the cluster
(more RWU) alone does NOT reduce the actor-count/parallelism ratio RisingWave
enforces (hard limit 400, soft limit 100 per worker) — every existing
adaptive-parallelism job silently rescales upward too, so the ratio stays
roughly constant. `ALTER ... SET PARALLELISM = n` applies to an already-running
job immediately, without dropping/recreating it (no backfill).

Strictly opt-in: defaults to a DRY RUN (prints the ALTER statements it would
run). Pass --apply to actually execute them.

Usage (run from the dbt/ directory):
    python scripts/set_parallelism.py <env> [--target N] [--apply] [--exclude name1,name2]

    env       dev | test | prod
    --target  desired parallelism (default: 1)
    --apply   actually run the ALTER statements (default: dry-run only)
    --exclude comma-separated object names to skip (e.g. a genuinely
              high-throughput job that should keep more parallelism)
    --confirm-prod   required together with --apply to target prod

Vault secrets: same convention as verify_sink_counts.py —
  kv/risingwave/<env>  ->  DBT_RW_HOST, DBT_RW_USER, DBT_RW_PASSWORD, DBT_RW_DBNAME
                          (falls back to kv/kdi/<env> RisingWaveSettings:* if not readable)

Requires: pip install psycopg2-binary
"""

import argparse
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# RisingWave catalog table -> ALTER keyword for objects of that type.
CATALOG_TO_ALTER_KEYWORD = {
    "rw_materialized_views": "MATERIALIZED VIEW",
    "rw_sinks": "SINK",
    "rw_tables": "TABLE",
    "rw_sources": "SOURCE",
}


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


def resolve_rw_creds(env):
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

    print(f"==> Vault       : {vault_server}")
    print("==> Fetching RisingWave credentials from Vault ...")

    kdi = vault_read(vault_server, vault_token, f"kdi/{env}")
    rw = vault_read(vault_server, vault_token, f"risingwave/{env}", optional=True)
    if rw and rw.get("DBT_RW_HOST"):
        return {
            "host": rw.get("DBT_RW_HOST", ""),
            "user": rw.get("DBT_RW_USER", "root"),
            "password": rw.get("DBT_RW_PASSWORD", ""),
            "dbname": rw.get("DBT_RW_DBNAME", env),
            "src": f"kv/risingwave/{env}",
        }
    return {
        "host": kdi.get("RisingWaveSettings:SqlHost", ""),
        "user": kdi.get("RisingWaveSettings:SqlUsername", "root"),
        "password": kdi.get("RisingWaveSettings:SqlPassword", ""),
        "dbname": env,
        "src": f"kv/kdi/{env} RisingWaveSettings",
    }


def collect_streaming_objects(cur, exclude):
    """Returns [(alter_keyword, name)] for every user-created streaming object."""
    objects = []
    for catalog_table, keyword in CATALOG_TO_ALTER_KEYWORD.items():
        cur.execute(f"SELECT name FROM rw_catalog.{catalog_table}")
        for (name,) in cur.fetchall():
            if name in exclude:
                continue
            objects.append((keyword, name))
    objects.sort(key=lambda t: (t[0], t[1]))
    return objects


def main():
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:
            pass

    parser = argparse.ArgumentParser(
        description="Sweep existing RisingWave streaming jobs down to an explicit low parallelism."
    )
    parser.add_argument("env", nargs="?", default="dev", choices=["dev", "test", "prod"])
    parser.add_argument("--target", type=int, default=1, help="desired parallelism (default: 1)")
    parser.add_argument("--apply", action="store_true", help="actually run the ALTER statements")
    parser.add_argument("--exclude", default="", help="comma-separated object names to skip")
    parser.add_argument("--confirm-prod", action="store_true", help="required with --apply to target prod")
    args = parser.parse_args()

    if args.env == "prod" and args.apply and not args.confirm_prod:
        print("REFUSING to apply against prod without --confirm-prod.", file=sys.stderr)
        sys.exit(2)

    exclude = {n.strip() for n in args.exclude.split(",") if n.strip()}

    creds = resolve_rw_creds(args.env)
    if not creds["host"]:
        print(f"ERROR: no RisingWave host found in Vault for env '{args.env}'", file=sys.stderr)
        sys.exit(1)

    try:
        import psycopg2
    except ImportError:
        print("ERROR: psycopg2 not installed — run: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)

    conn = psycopg2.connect(
        host=creds["host"], port=4566, dbname=creds["dbname"],
        user=creds["user"], password=creds["password"],
        sslmode="require", connect_timeout=15,
    )
    conn.autocommit = True
    print(f"==> RisingWave  : {creds['host']}:4566/{creds['dbname']} ({creds['src']})")

    with conn.cursor() as cur:
        objects = collect_streaming_objects(cur, exclude)
        print(f"==> Found {len(objects)} streaming object(s). Target parallelism: {args.target}")
        if not objects:
            return

        mode = "APPLYING" if args.apply else "DRY RUN — pass --apply to execute"
        print(f"==> Mode: {mode}\n")

        succeeded, failed = 0, 0
        for keyword, name in objects:
            stmt = f'ALTER {keyword} "{name}" SET PARALLELISM = {args.target};'
            if not args.apply:
                print(f"  would run: {stmt}")
                continue
            try:
                cur.execute(stmt)
                print(f"  OK      {stmt}")
                succeeded += 1
            except Exception as exc:
                print(f"  FAILED  {stmt}  ({exc})", file=sys.stderr)
                failed += 1

        if args.apply:
            print(f"\n==> Done: {succeeded} succeeded, {failed} failed.")

    conn.close()


if __name__ == "__main__":
    main()
