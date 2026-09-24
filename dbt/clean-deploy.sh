#!/bin/bash
# dbt/clean-deploy.sh — Drop all RisingWave objects and redeploy from scratch
#
# USE CASE: When --full-refresh causes RisingWave barrier failures (CDC sources).
# Drops objects in dependency order (sinks → MVs → tables → sources),
# then runs a full fresh deploy.
#
# Usage (run from the dbt/ directory):
#   ./clean-deploy.sh [env]
#
# Examples:
#   ./clean-deploy.sh dev    # wipe + redeploy dev
#   ./clean-deploy.sh test
#
# WARNING: Only use in dev/test — never prod.

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
cd "$SCRIPT_DIR"

ENV="${1:-dev}"

case "$ENV" in
  dev)
    ENV_FILE="$SCRIPT_DIR/../.env.development"
    DBNAME="dev"
    ;;
  test)
    ENV_FILE="$SCRIPT_DIR/../.env.test"
    DBNAME="test"
    ;;
  *)
    echo "ERROR: clean-deploy only supports dev and test (not prod)." >&2
    exit 1
    ;;
esac

[ ! -f "$ENV_FILE" ] && { echo "ERROR: env file not found: $ENV_FILE" >&2; exit 1; }

echo "==> Environment : $ENV"
echo "==> WARNING: This will drop ALL objects in '$DBNAME.public' and redeploy."
read -r -p "==> Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" != "yes" ] && { echo "Aborted."; exit 1; }

PYTHON=$(which python3 2>/dev/null || which python 2>/dev/null || true)
[ -z "$PYTHON" ] && { echo "ERROR: python not found." >&2; exit 1; }

eval "$("$PYTHON" - "$ENV_FILE" <<'PYEOF'
import sys
env_file = sys.argv[1]
with open(env_file) as f:
    for line in f:
        line = line.rstrip('\n')
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, _, value = line.partition('=')
        key = key.strip()
        if key in ('DBT_RW_HOST', 'DBT_RW_USER', 'DBT_RW_PASSWORD'):
            escaped = value.strip().replace("'", "'\\''")
            print(f"export {key}='{escaped}'")
PYEOF
)"

PSQL_CONN="host=$DBT_RW_HOST port=4566 user=$DBT_RW_USER dbname=$DBNAME sslmode=require"

run_psql() {
    PGPASSWORD="$DBT_RW_PASSWORD" psql "$PSQL_CONN" -v ON_ERROR_STOP=0 -c "$1"
}

run_psql_file() {
    PGPASSWORD="$DBT_RW_PASSWORD" psql "$PSQL_CONN" -v ON_ERROR_STOP=0 -f "$1"
}

echo ""
echo "==> Step 1/4: Dropping sinks ..."
run_psql "
SELECT 'DROP SINK IF EXISTS public.\"' || s.name || '\";'
FROM rw_catalog.rw_sinks s
JOIN rw_catalog.rw_schemas sc ON s.schema_id = sc.id
WHERE sc.name = 'public';
" | grep 'DROP SINK' > /tmp/rw_drop_sinks.sql || true

if [ -s /tmp/rw_drop_sinks.sql ]; then
    echo "   Dropping: $(wc -l < /tmp/rw_drop_sinks.sql) sinks"
    run_psql_file /tmp/rw_drop_sinks.sql
else
    echo "   No sinks found."
fi

echo ""
echo "==> Step 2/4: Dropping materialized views ..."
run_psql "
SELECT 'DROP MATERIALIZED VIEW IF EXISTS public.\"' || mv.name || '\";'
FROM rw_catalog.rw_materialized_views mv
JOIN rw_catalog.rw_schemas sc ON mv.schema_id = sc.id
WHERE sc.name = 'public';
" | grep 'DROP MATERIALIZED' > /tmp/rw_drop_mvs.sql || true

if [ -s /tmp/rw_drop_mvs.sql ]; then
    echo "   Dropping: $(wc -l < /tmp/rw_drop_mvs.sql) materialized views"
    run_psql_file /tmp/rw_drop_mvs.sql
else
    echo "   No materialized views found."
fi

echo ""
echo "==> Step 3/4: Dropping tables ..."
run_psql "
SELECT 'DROP TABLE IF EXISTS public.\"' || t.name || '\";'
FROM rw_catalog.rw_tables t
JOIN rw_catalog.rw_schemas sc ON t.schema_id = sc.id
WHERE sc.name = 'public';
" | grep 'DROP TABLE' > /tmp/rw_drop_tables.sql || true

if [ -s /tmp/rw_drop_tables.sql ]; then
    echo "   Dropping: $(wc -l < /tmp/rw_drop_tables.sql) tables"
    run_psql_file /tmp/rw_drop_tables.sql
else
    echo "   No tables found."
fi

echo ""
echo "==> Step 4/4: Dropping sources ..."
run_psql "
SELECT 'DROP SOURCE IF EXISTS public.\"' || s.name || '\";'
FROM rw_catalog.rw_sources s
JOIN rw_catalog.rw_schemas sc ON s.schema_id = sc.id
WHERE sc.name = 'public';
" | grep 'DROP SOURCE' > /tmp/rw_drop_sources.sql || true

if [ -s /tmp/rw_drop_sources.sql ]; then
    echo "   Dropping: $(wc -l < /tmp/rw_drop_sources.sql) sources"
    run_psql_file /tmp/rw_drop_sources.sql
else
    echo "   No sources found."
fi

echo ""
echo "==> All objects dropped. Running fresh deploy ..."
./deploy.sh "$ENV" --seed
