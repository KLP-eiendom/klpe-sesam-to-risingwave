#!/usr/bin/env bash
# dbt/fast-test.sh — Incremental E2E test runner (skips Docker teardown)
#
# Re-deploys changed models, reloads test data, and runs verify_e2e.py.
# Starts RisingWave if it isn't running, but never tears it down — existing
# materialized view state is preserved between runs, making iteration fast.
#
# Use this when:
#   - Iterating on a model or sink after the initial full deploy
#   - Checking whether a specific model fix resolves an E2E failure
#   - You want results in ~30s instead of the full 2-3 min of run-test.sh
#
# Usage (run from the dbt/ directory):
#   ./fast-test.sh                                   # redeploy all models
#   ./fast-test.sh --select mrt_global_customer+     # redeploy a model and its dependants
#   ./fast-test.sh --select models/sinks             # redeploy sinks only
#
# Steps:
#   1. Start RisingWave if not already running
#   2. dbt seed       — reload static reference data
#   3. dbt run        — deploy models (all or --select subset)
#   4. load_test_data — INSERT test rows into staging tables
#   5. Wait 5s        — allow materialized views to refresh
#   6. verify_e2e     — compare sink views against expected_data/*.json

set -euo pipefail

# ── Compose file location ─────────────────────────────────────────────────────
# docker-compose.yml lives at the repo root, one level up from dbt/ (where this
# script expects to be run from) — point `docker compose` at it explicitly.
export COMPOSE_FILE="../docker-compose.yml"

# ── Load env from .env.localdev ───────────────────────────────────────────────
# We load this early to allow overrides for DBT_BIN/PYTHON_BIN
if [[ -f "../.env.localdev" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed_line=$(echo "$line" | sed 's/[[:space:]]*$//')
    if [[ "$trimmed_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      export "$trimmed_line"
    fi
  done < "../.env.localdev"
fi

# ── Tool Discovery ────────────────────────────────────────────────────────────
# Default to commands in PATH, but allow override via env vars
DBT=${DBT_BIN:-dbt}
PYTHON=${PYTHON_BIN:-python}

# Fallback for python3 vs python
if ! command -v "$PYTHON" &> /dev/null; then
  if command -v python3 &> /dev/null; then
    PYTHON="python3"
  fi
fi

# Robust discovery for dbt if not in PATH (common on Windows Python installs)
if ! command -v "$DBT" &> /dev/null; then
  # Try to discover via Python (portable across Windows users)
  DISCOVERED_DBT=$($PYTHON -c "import os; p=os.path.join(os.environ.get('APPDATA', ''), 'Python', 'Python312', 'Scripts', 'dbt'); print(p.replace('\\\\', '/')) if os.path.exists(p) or os.path.exists(p+'.exe') else print('')" 2>/dev/null)
  
  if [[ -n "$DISCOVERED_DBT" ]]; then
    # Convert C:/ style to /c/ for Bash compatibility if needed
    DBT=$(echo "$DISCOVERED_DBT" | sed 's/^\([A-Za-z]\):/\/\L\1/')
  fi
fi

echo "==> Using DBT: $DBT"
echo "==> Using PYTHON: $PYTHON"

# ── Capture DBT arguments ─────────────────────────────────────────────────────
# If no arguments provided, default to staging and marts
DBT_ARGS=("$@")
if [[ ${#DBT_ARGS[@]} -eq 0 ]]; then
  DBT_ARGS=("--select" "models/staging" "models/marts" "models/sinks")
fi

echo "==> Fast-tracking: Deploying models, loading test data and verifying..."

# ── 0. Ensure RisingWave is running (start if needed, no teardown) ────────────
RW_STATUS=$(docker compose ps --status running --services 2>/dev/null | grep -x risingwave || true)
if [[ -z "$RW_STATUS" ]]; then
  echo ""
  echo "==> RisingWave not running — starting..."
  docker compose up -d risingwave
  echo "==> Waiting for RisingWave to accept connections..."
  timeout 90 bash -c 'until docker compose exec -T postgres psql -h risingwave -p 4566 -U root -d dev -c "SELECT 1" -q 2>/dev/null; do sleep 3; done'
  echo "    RisingWave is ready."
else
  echo "    RisingWave already running."
fi

# ── 1. Seed static reference data ────────────────────────────────────────────
echo ""
echo "==> Seeding static reference data..."
$DBT seed --target localdev --no-partial-parse

# ── 2. Deploy staging + mart models (no CDC sources, no sinks) ───────────────
echo ""
echo "==> Deploying models with: ${DBT_ARGS[*]}"
$DBT run --target localdev \
  "${DBT_ARGS[@]}" \
  --no-partial-parse

# ── 3. Load test data into staging tables ────────────────────────────────────
echo ""
echo "==> Loading test data into staging tables..."
$PYTHON scripts/load_test_data.py

# ── 4. Wait for materialized views to refresh ─────────────────────────────────
echo ""
echo "==> Waiting for materialized views to refresh..."
sleep 5

# ── 5. E2E verification: mart output vs expected_data ─────────────────────────
echo ""
echo "==> Running E2E verification..."
$PYTHON scripts/verify_e2e.py

echo ""
echo "Fast test complete."
