#!/usr/bin/env bash
# dbt/run-test.sh — Full local E2E test suite (clean slate)
#
# Tears down and restarts RisingWave via Docker Compose, deploys all models
# from scratch, loads test data, and runs verify_e2e.py against every sink.
#
# Use this when:
#   - First run on a new machine or after schema changes
#   - You need a completely clean state (no stale MV data)
#   - Running the full regression suite before opening a PR
#
# For faster iteration after the initial deploy, use fast-test.sh instead.
#
# Usage (run from the dbt/ directory):
#   ./run-test.sh
#
# Prerequisites:
#   - Docker Desktop running
#   - dbt installed (auto-discovered if not in PATH)
#   - Python 3 with psycopg2 installed
#   - ../.env.localdev present (copy from .env.localdev.example)
#
# Steps:
#   1. Start RisingWave (docker compose down + up)
#   2. dbt seed       — load static reference data (fdvweb_helper_energy, etc.)
#   3. dbt run        — deploy staging + marts + sinks (sinks materialized as views in localdev)
#   4. load_test_data — INSERT test rows into staging tables
#   5. Wait 5s        — allow materialized views to refresh
#   6. verify_e2e     — compare sink views against expected_data/*.json

if [[ -n "$CI" || -n "$TF_BUILD" ]]; then
  echo "ERROR: run-test.sh is a local dev script. Use azure-pipelines-ci.yml for CI." >&2
  exit 1
fi

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
  echo "==> dbt not in PATH, attempting to discover..."
  
  # Try to discover via Python (portable across Windows users)
  DISCOVERED_DBT=$($PYTHON -c "import os; p=os.path.join(os.environ.get('APPDATA', ''), 'Python', 'Python312', 'Scripts', 'dbt'); print(p.replace('\\\\', '/')) if os.path.exists(p) or os.path.exists(p+'.exe') else print('')" 2>/dev/null)
  
  if [[ -n "$DISCOVERED_DBT" ]]; then
    # Convert C:/ style to /c/ for Bash compatibility if needed
    DBT=$(echo "$DISCOVERED_DBT" | sed 's/^\([A-Za-z]\):/\/\L\1/')
    echo "    Found dbt at: $DBT"
  else
    echo "ERROR: 'dbt' command not found. Please ensure dbt is installed or set DBT_BIN in .env.localdev"
    exit 1
  fi
fi

echo "==> Using DBT: $DBT"
echo "==> Using PYTHON: $PYTHON"

# ── 1. Start RisingWave via docker compose ────────────────────────────────────
echo ""
echo "==> Starting RisingWave..."
docker compose down --remove-orphans
docker compose up -d

echo "==> Waiting for RisingWave to accept connections..."
# Check health using psql from the postgres container
timeout 90 bash -c 'until docker compose exec -T postgres psql -h risingwave -p 4566 -U root -d dev -c "SELECT 1" -q 2>/dev/null; do sleep 3; done'
echo "    RisingWave is ready."

# ── 2. Seed static reference data (e.g. fdvweb_helper_energy) ────────────────
echo ""
echo "==> Seeding static reference data..."
$DBT seed --target localdev --no-partial-parse

# ── 3. Deploy staging + mart + sink models (sinks as views in localdev) ──────
echo ""
echo "==> Deploying staging and mart models..."
$DBT run --target localdev \
  --select models/staging models/marts models/sinks \
  --no-partial-parse

# ── 4. Run dbt unit tests ────────────────────────────────────────────────────
echo ""
echo "==> Running dbt unit tests..."
$DBT test --target localdev --no-partial-parse

# ── 5. Load test data into staging tables ────────────────────────────────────
echo ""
echo "==> Loading test data into staging tables..."
$PYTHON scripts/load_test_data.py

# ── 6. Wait for materialized views to refresh ─────────────────────────────────
echo ""
echo "==> Waiting for materialized views to refresh..."
sleep 5

# ── 7. E2E verification: mart output vs expected_data ─────────────────────────
echo ""
echo "==> Running E2E verification..."
$PYTHON scripts/verify_e2e.py

echo ""
echo "All done."
