#!/bin/bash
# dbt/clean.sh — Drop ALL RisingWave objects (sinks → MVs → tables → sources)
#
# Use before a full clean redeploy, or when resource contention from CDC +
# sink connectors requires a hard reset.
#
# Usage (run from the dbt/ directory):
#   ./clean.sh [env]
#
# Examples:
#   ./clean.sh dev     # clean dev (default)
#   ./clean.sh test    # clean test
#   ./clean.sh prod    # clean prod (requires explicit confirmation)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV="${1:-dev}"
case "$ENV" in
  dev)
    ENV_FILE="$SCRIPT_DIR/../.env.development"
    GKE_CLUSTER="cluster-dev"
    GKE_PROJECT="example-project-dev"
    DBNAME="dev"
    ;;
  test)
    ENV_FILE="$SCRIPT_DIR/../.env.test"
    GKE_CLUSTER="cluster-test"
    GKE_PROJECT="example-project-test"
    DBNAME="test"
    ;;
  prod)
    ENV_FILE="$SCRIPT_DIR/../.env.production"
    GKE_CLUSTER="cluster-prod"
    GKE_PROJECT="example-project-prod"
    DBNAME="prod"
    ;;
  *)
    echo "ERROR: unknown environment '$ENV'. Use: dev | test | prod" >&2
    exit 1
    ;;
esac

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: env file not found: $ENV_FILE" >&2
    exit 1
fi

echo "==> Environment : $ENV  (db=$DBNAME)"
echo "==> Env file    : $ENV_FILE"
echo ""
echo "WARNING: This will DROP ALL sinks, materialized views, tables, and sources"
echo "         in the '$ENV' RisingWave environment. All data will be lost."
echo ""
read -rp "Type 'yes' to confirm: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# ── Detect cloud vs localdev ──────────────────────────────────────────────────
CLOUD_HOST=$(grep '^DBT_RW_HOST=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)

if [ -n "$CLOUD_HOST" ] && [ "$CLOUD_HOST" != "localhost" ]; then
    echo "==> Cloud endpoint : $CLOUD_HOST"
    USE_PORT_FORWARD=false
else
    echo "==> GKE cluster    : $GKE_CLUSTER ($GKE_PROJECT)"
    USE_PORT_FORWARD=true

    if ! kubectl config get-contexts "gke_${GKE_PROJECT}_europe-north1_${GKE_CLUSTER}" &>/dev/null; then
        echo "==> Fetching cluster credentials ..."
        gcloud container clusters get-credentials "$GKE_CLUSTER" \
            --project="$GKE_PROJECT" --region=europe-north1
    fi
    kubectl config use-context "gke_${GKE_PROJECT}_europe-north1_${GKE_CLUSTER}" &>/dev/null

    PF_PID=""
    if (echo > /dev/tcp/localhost/4566) 2>/dev/null; then
        echo "==> Port 4566 already open — skipping port-forward."
    else
        echo "==> Starting kubectl port-forward ..."
        kubectl port-forward svc/risingwave-frontend-service 4566:4566 -n default &
        PF_PID=$!
        trap 'echo "==> Stopping port-forward (PID $PF_PID)..."; kill "$PF_PID" 2>/dev/null' EXIT

        for i in $(seq 1 15); do
            if (echo > /dev/tcp/localhost/4566) 2>/dev/null; then
                echo "==> Port-forward ready."
                break
            fi
            [ "$i" -eq 15 ] && { echo "ERROR: port-forward did not become ready in time." >&2; exit 1; }
            sleep 1
        done
    fi
fi

echo ""
echo "==> Dropping all objects ..."
echo ""

python3 - "$DBNAME" "$ENV_FILE" "$USE_PORT_FORWARD" <<'PYEOF'
import subprocess, os, sys

dbname           = sys.argv[1]
env_file         = sys.argv[2]
use_port_forward = sys.argv[3] == 'true'

env = os.environ.copy()
with open(env_file) as f:
    for line in f:
        line = line.rstrip('\n')
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, _, value = line.partition('=')
        env[key.strip()] = value.strip()

if use_port_forward:
    host     = 'localhost'
    user     = 'root'
    password = ''
else:
    host     = env.get('DBT_RW_HOST', '')
    user     = env.get('DBT_RW_USER', 'root')
    password = env.get('DBT_RW_PASSWORD', '')

env['PGPASSWORD'] = password
env['PGSSLMODE']  = 'require' if not use_port_forward else 'prefer'

psql_base = ['psql', '-h', host, '-p', '4566', '-U', user, '-d', dbname, '-v', 'ON_ERROR_STOP=0']

# Drop order: sinks → materialized views → tables → sources
# Each step uses \gexec to execute the generated DROP statements.
steps = [
    ("sinks",              "SELECT 'DROP SINK IF EXISTS ' || quote_ident(name) || ' CASCADE;' FROM rw_catalog.rw_sinks;"),
    ("materialized views", "SELECT 'DROP MATERIALIZED VIEW IF EXISTS ' || quote_ident(name) || ' CASCADE;' FROM rw_catalog.rw_materialized_views;"),
    ("tables",             "SELECT 'DROP TABLE IF EXISTS ' || quote_ident(name) || ' CASCADE;' FROM rw_catalog.rw_tables;"),
    ("sources",            "SELECT 'DROP SOURCE IF EXISTS ' || quote_ident(name) || ' CASCADE;' FROM rw_catalog.rw_sources;"),
]

for label, query in steps:
    print(f"  Dropping {label} ...")
    sql = query + r" \gexec"
    result = subprocess.run(psql_base + ['-c', sql], env=env, capture_output=True, text=True)
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.returncode != 0 and result.stderr.strip():
        print(f"  (warnings: {result.stderr.strip()})")

print("")
print("==> Clean complete. Run ./deploy.sh to redeploy.")
PYEOF
