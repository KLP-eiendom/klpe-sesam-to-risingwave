#!/bin/bash
# dbt/deploy.sh — Deploy dbt models to dev / test / prod
#
# Connects directly to RisingWave Cloud using DBT_RW_* from the .env file.
#
# Usage (run from the dbt/ directory):
#   ./deploy.sh [env] [dbt args...]
#
# Examples:
#   ./deploy.sh                              # smart deploy to dev (only changed models + downstream)
#   ./deploy.sh dev --dry-run                # show what smart deploy would do — no actual deploy
#   ./deploy.sh dev --all                    # force deploy all models to dev
#   ./deploy.sh dev --select stg_foo         # manual select (bypasses smart deploy)
#   ./deploy.sh dev --select stg_foo --full-refresh
#   ./deploy.sh test                         # smart deploy to test
#   ./deploy.sh prod                         # smart deploy to prod
#
# Smart Deployment (dev, test, prod only):
#   If no --select is provided, the script automatically detects changed models 
#   using hashes and runs them with --full-refresh (plus downstream dependencies).
#   State is stored in dbt/state/manifest_<env>.json.
#
# .env files:
#   dev  → ../.env.development
#   test → ../.env.test
#   prod → ../.env.production
#
# ── Operational notes ────────────────────────────────────────────────────────
#
# BACKGROUND_DDL (initial deploy / new MVs on large tables):
#   Creating a materialized view over a table with many existing rows blocks the
#   session until the backfill completes. On the first deploy to a new environment,
#   or when adding new MVs over large tables, connect to RisingWave manually first:
#
#     psql -h localhost -p 4566 -d dev -U root
#     SET BACKGROUND_DDL = true;
#     SELECT ddl_id, ddl_statement, progress FROM rw_catalog.rw_ddl_progress;
#
#   The setting is session-scoped — it must be set before each DDL statement.
#
# SINK SNAPSHOT POLICY (re-deploying an existing sink):
#   By default, creating a sink replays all current MV data into MySQL (backfill).
#   This is correct on initial deploy (MySQL tables start empty).
#   When re-deploying a sink after a schema change, drop and recreate it manually
#   to avoid re-sending millions of rows:
#
#     DROP SINK IF EXISTS public.snk_<name>;
#     -- Then run deploy.sh normally — dbt will recreate the sink.
#
#   See TESTING.md § "Sink Deployment Strategy" for the full decision table.

set -euo pipefail
# set -x

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
cd "$SCRIPT_DIR"

# ── Tool Discovery ────────────────────────────────────────────────────────────
# Support running across different developer machine setups.
# DBT_BIN / PYTHON_BIN override everything below — same escape hatch fast-test.sh has.
DBT=${DBT_BIN:-$(which dbt 2>/dev/null || true)}
PYTHON=${PYTHON_BIN:-$(which python3 2>/dev/null || which python 2>/dev/null || true)}

if [ -z "$DBT" ] || [ -z "$PYTHON" ]; then
    POTENTIAL_PYTHON_PATHS=(
        "/mnt/c/Python312/python.exe"
        "$HOME/AppData/Local/Programs/Python/Python312/python.exe"
        "/c/Users/${USER:-${USERNAME:-}}/AppData/Local/Programs/Python/Python312/python.exe"
        "$HOME/AppData/Local/Microsoft/WindowsApps/python.exe"
        "/c/Python312/python.exe"
        "/c/Users/${USER:-${USERNAME:-}}/AppData/Local/Microsoft/WindowsApps/python.exe"
    )
    for p in "${POTENTIAL_PYTHON_PATHS[@]}"; do
        if [ -x "$p" ]; then PYTHON="$p"; break; fi
    done

    # If we found Python, try to find dbt in its Scripts directory
    if [ -n "$PYTHON" ]; then
        py_dir=$(dirname "$PYTHON")
        if [ -x "$py_dir/Scripts/dbt.exe" ]; then
            DBT="$py_dir/Scripts/dbt.exe"
        elif [ -x "$py_dir/dbt.exe" ]; then
            DBT="$py_dir/dbt.exe"
        fi
    fi
fi

# Final fallback for DBT if still not found
if [ -z "$DBT" ]; then
    POTENTIAL_DBT_PATHS=(
        "/mnt/c/Users/tvtle/AppData/Roaming/Python/Python312/Scripts/dbt.exe"
        "$HOME/AppData/Local/Programs/Python/Python312/Scripts/dbt.exe"
        "/c/Users/${USER:-${USERNAME:-}}/AppData/Local/Programs/Python/Python312/Scripts/dbt.exe"
        "$HOME/AppData/Roaming/Python/Python312/Scripts/dbt.exe"
        "/c/Users/${USER:-${USERNAME:-}}/AppData/Roaming/Python/Python312/Scripts/dbt.exe"
    )
    for p in "${POTENTIAL_DBT_PATHS[@]}"; do
        if [ -x "$p" ]; then DBT="$p"; break; fi
    done
fi

# Layout-aware fallback. The lists above are hardcoded to Python 3.12 in the classic
# install locations; a Microsoft Store Python puts the interpreter under
# WindowsApps/ but its console scripts in a completely different tree
# (Packages/<pkg>/LocalCache/local-packages/PythonXY/Scripts), so `$py_dir/Scripts`
# never resolves there. Globs keep this working across versions.
if [ -z "$DBT" ]; then
    for p in         "$HOME"/AppData/Local/Packages/PythonSoftwareFoundation.Python.*/LocalCache/local-packages/Python*/Scripts/dbt.exe         "$HOME"/AppData/Roaming/Python/Python*/Scripts/dbt.exe         "$HOME"/AppData/Local/Programs/Python/Python*/Scripts/dbt.exe         /c/Users/"${USER:-${USERNAME:-}}"/AppData/Local/Packages/PythonSoftwareFoundation.Python.*/LocalCache/local-packages/Python*/Scripts/dbt.exe         /c/Users/"${USER:-${USERNAME:-}}"/AppData/Roaming/Python/Python*/Scripts/dbt.exe ; do
        if [ -x "$p" ]; then DBT="$p"; break; fi
    done
fi

[ -z "$DBT" ] && {
    echo "ERROR: dbt not found. Install it, add it to PATH, or point DBT_BIN at the executable:" >&2
    echo "  DBT_BIN=/path/to/dbt.exe ./deploy.sh $*" >&2
    exit 1
}
[ -z "$PYTHON" ] && { echo "ERROR: python not found. Please install it or add it to PATH." >&2; exit 1; }

# Fix for gsutil on Windows: ensure it uses the discovered Python
export CLOUDSDK_PYTHON="$PYTHON"

# ── Resolve environment ───────────────────────────────────────────────────────
ENV="${1:-dev}"
case "$ENV" in
  dev)
    ENV_FILE="$SCRIPT_DIR/../.env.development"
    GKE_CLUSTER="cluster-dev"
    GKE_PROJECT="example-project-dev"
    DBT_TARGET="dev"
    ;;
  test)
    ENV_FILE="$SCRIPT_DIR/../.env.test"
    GKE_CLUSTER="cluster-test"
    GKE_PROJECT="example-project-test"
    DBT_TARGET="test"
    ;;
  prod)
    ENV_FILE="$SCRIPT_DIR/../.env.production"
    GKE_CLUSTER="cluster-prod"
    GKE_PROJECT="example-project-prod"
    DBT_TARGET="prod"
    ;;
  localdev)
    ENV_FILE="$SCRIPT_DIR/../.env.localdev"
    GKE_CLUSTER=""
    GKE_PROJECT=""
    DBT_TARGET="localdev"
    ;;
  *)
    echo "ERROR: unknown environment '$ENV'. Use: dev | test | prod" >&2
    exit 1
    ;;
esac

# Consume the env arg so remaining $@ are passed through to dbt
shift || true

echo "==> Environment : $ENV  (target=$DBT_TARGET)"
if [ -f "$ENV_FILE" ]; then
    echo "==> Env file    : $ENV_FILE"
else
    echo "==> Env file    : $ENV_FILE (not found, using shell environment)"
fi

# ── Fetch secrets from Vault ──────────────────────────────────────────────────
LOCALDEV_FILE="$SCRIPT_DIR/../.env.localdev"
RESOLVED_ENV=$(mktemp)
chmod 600 "$RESOLVED_ENV"

_cleanup() {
    [ -n "${PF_PID:-}" ] && { echo "==> Stopping port-forward (PID $PF_PID)..."; kill "$PF_PID" 2>/dev/null; }
    rm -f "$RESOLVED_ENV"
}
trap '_cleanup' EXIT

if [ "$ENV" = "localdev" ]; then
    echo "==> Localdev: skipping Vault, copying env file directly ..."
    cp "$ENV_FILE" "$RESOLVED_ENV"
else
    echo "==> Fetching secrets from Vault ..."
    # Convert paths to Windows format if we are in a shell that supports cygpath (like Git Bash)
    W_ENV_FILE="$ENV_FILE"
    W_LOCALDEV_FILE="$LOCALDEV_FILE"
    W_SCRIPT_PATH="$SCRIPT_DIR/scripts/fetch_vault_secrets.py"
    if command -v cygpath >/dev/null 2>&1; then
        W_ENV_FILE=$(cygpath -w "$ENV_FILE")
        W_LOCALDEV_FILE=$(cygpath -w "$LOCALDEV_FILE")
        W_SCRIPT_PATH=$(cygpath -w "$SCRIPT_DIR/scripts/fetch_vault_secrets.py")
    elif command -v wslpath >/dev/null 2>&1; then
        W_ENV_FILE=$(wslpath -w "$ENV_FILE")
        W_LOCALDEV_FILE=$(wslpath -w "$LOCALDEV_FILE")
        W_SCRIPT_PATH=$(wslpath -w "$SCRIPT_DIR/scripts/fetch_vault_secrets.py")
    fi
    "$PYTHON" "$W_SCRIPT_PATH" "$W_ENV_FILE" "$W_LOCALDEV_FILE" > "$RESOLVED_ENV"
fi

# ── Detect cloud vs localdev ──────────────────────────────────────────────────
# DBT_RW_HOST comes from Vault (resolved into $RESOLVED_ENV).
CLOUD_HOST=$(grep "DBT_RW_HOST=" "$RESOLVED_ENV" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"\r ' || true)

if [ -n "$CLOUD_HOST" ] && [ "$CLOUD_HOST" != "localhost" ]; then
    echo "==> Cloud endpoint detected: $CLOUD_HOST"
    echo "==> Skipping kubectl / port-forward (direct connection)."
    USE_PORT_FORWARD=false
elif [ "$ENV" = "localdev" ]; then
    echo "==> Localdev environment detected."
    echo "==> Skipping GKE / kubectl steps."
    USE_PORT_FORWARD=false
else
    echo "==> GKE cluster    : $GKE_CLUSTER ($GKE_PROJECT)"
    USE_PORT_FORWARD=true   

    # ── Ensure kubectl context ────────────────────────────────────────────────
    if ! kubectl config get-contexts "gke_${GKE_PROJECT}_europe-north1_${GKE_CLUSTER}" &>/dev/null; then
        echo "==> Fetching cluster credentials ..."
        gcloud container clusters get-credentials "$GKE_CLUSTER" \
            --project="$GKE_PROJECT" --region=europe-north1
    fi
    kubectl config use-context "gke_${GKE_PROJECT}_europe-north1_${GKE_CLUSTER}" &>/dev/null

    # ── Port-forward ──────────────────────────────────────────────────────────
    PF_PID=""

    if (echo > /dev/tcp/localhost/4566) 2>/dev/null; then
        echo "==> Port 4566 already open — skipping port-forward."
    else
        echo "==> Starting kubectl port-forward ..."
        kubectl port-forward svc/risingwave-frontend-service 4566:4566 -n default &
        PF_PID=$!

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

# ── State Sync (Download from GCS) ───────────────────────────────────────────
# STATE_BUCKET is derived from GCS_BIGQUERY_STAGING_BUCKET in Vault
if [ -z "${STATE_BUCKET:-}" ]; then
    _gcs=$(grep '^GCS_BIGQUERY_STAGING_BUCKET=' "$RESOLVED_ENV" 2>/dev/null | cut -d= -f2- || true)
    [ -n "$_gcs" ] && STATE_BUCKET="${_gcs}/dbt-state"
fi
if [ -n "${STATE_BUCKET:-}" ]; then
    echo "==> Syncing state from gs://$STATE_BUCKET/manifest_$ENV.json ..."
    mkdir -p state
    # Remove stale temp files left by interrupted gsutil downloads
    rm -f "state/manifest_$ENV.json_.gstmp"
    # Download atomically: preserve existing local state if GCS download fails
    if gsutil cp "gs://$STATE_BUCKET/manifest_$ENV.json" "state/manifest_$ENV.json.dl" 2>/dev/null; then
        mv "state/manifest_$ENV.json.dl" "state/manifest_$ENV.json"
    else
        rm -f "state/manifest_$ENV.json.dl"
        echo "==> No previous state found in bucket (using local state if available)."
    fi
fi

# ── dbt run ───────────────────────────────────────────────────────────────────
# Python parses the .env file — values contain JSON / special bash chars that
# break both `export $(... | xargs)` and `set -a; source .env`.

echo "==> Running: $DBT [seed +] run --target $DBT_TARGET $*"
echo ""

W_RESOLVED_ENV="$RESOLVED_ENV"
W_PYTHON="$PYTHON"
W_DBT="$DBT"
if command -v cygpath >/dev/null 2>&1; then
    W_RESOLVED_ENV=$(cygpath -w "$RESOLVED_ENV")
    W_PYTHON=$(cygpath -w "$PYTHON")
    W_DBT=$(cygpath -w "$DBT")
elif command -v wslpath >/dev/null 2>&1; then
    W_RESOLVED_ENV=$(wslpath -w "$RESOLVED_ENV")
    W_PYTHON=$(wslpath -w "$PYTHON")
    W_DBT=$(wslpath -w "$DBT")
fi

"$PYTHON" - "$DBT_TARGET" "$W_RESOLVED_ENV" "$USE_PORT_FORWARD" "$W_DBT" "$@" <<'PYEOF'
import subprocess, os, sys

dbt_target      = sys.argv[1]
env_file        = sys.argv[2]
use_port_forward = sys.argv[3] == 'true'
dbt_path        = sys.argv[4]
extra_args      = sys.argv[5:]

# --seed flag: run `dbt seed` before `dbt run`
run_seed = '--seed' in extra_args
if run_seed:
    extra_args = [a for a in extra_args if a != '--seed']

env = os.environ.copy()
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, _, value = line.partition('=')
            k = key.strip()
            if k not in env:
                env[k] = value.strip()

# Warm up Azure SQL Serverless database to prevent 'not currently available' (40613) errors
if dbt_target not in ('localdev', 'ci') and env.get('POWERAPP_SINK_MODE', 'running').lower() != 'paused':
    mssql_host = env.get('POWERAPP_MSSQL_HOST')
    mssql_db = env.get('POWERAPP_MSSQL_DB')
    mssql_user = env.get('POWERAPP_MSSQL_USER')
    mssql_password = env.get('POWERAPP_MSSQL_PASSWORD')
    if mssql_host and mssql_host != 'localhost':
        def warm_up_mssql(host, db, user, password):
            import socket, time
            print(f"==> Waking up Azure SQL Database '{db}' on '{host}' (checking port 1433)...")
            try:
                s = socket.create_connection((host, 1433), timeout=5)
                s.close()
            except Exception as e:
                print(f"==> Warning: Could not TCP ping {host}: {e}")
                return

            if os.name == 'nt':
                print("==> Windows detected. Performing ADO.NET connection retries until database is online...")
                ps_code = f"""
$connString = "Server={host};Database={db};User ID={user};Password={password};Encrypt=true;TrustServerCertificate=true;Connection Timeout=10;"
$seconds = 0
$maxSeconds = 120
while ($seconds -lt $maxSeconds) {{
    try {{
        $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
        $conn.Open()
        $conn.Close()
        exit 0
    }} catch {{
        Start-Sleep -Seconds 5
        $seconds += 5
    }}
}}
exit 1
"""
                try:
                    res = subprocess.run(
                        ["powershell", "-NoProfile", "-Command", "-"],
                        input=ps_code,
                        text=True,
                        capture_output=True
                    )
                    if res.returncode == 0:
                        print("==> Database is fully awake and ready.")
                    else:
                        print("==> Warning: Database warm-up timed out. Proceeding anyway...")
                except Exception as e:
                    print(f"==> Warning: Failed to run PowerShell warm-up: {e}")
                    print("==> Waiting 45 seconds to let database resume...")
                    time.sleep(45)
            else:
                print("==> Non-Windows detected. Waiting 45 seconds to allow database to resume...")
                time.sleep(45)

        warm_up_mssql(mssql_host, mssql_db, mssql_user, mssql_password)

if use_port_forward:
    # Localdev / Port-forward fallback: always connect via localhost; cluster user is root/no-password
    env['DBT_RW_HOST'] = 'localhost'
    env['DBT_RW_USER'] = 'root'
    env['DBT_RW_PASSWORD'] = ''
# Cloud: DBT_RW_HOST / DBT_RW_USER / DBT_RW_PASSWORD come from the .env file as-is

# -- Sink Exclusion Logic based on SINK_MODE vars --
sink_groups = {
    'FORVALTER_SINK_MODE':   '*snk*forvalter',
    'KUNDEPORTAL_SINK_MODE': '*snk*kundeportal',
    'SUPEROFFICE_SINK_MODE': '*snk*superoffice',
    'BQ_SINK_MODE':          '*snk*bq *snk*bqeos',
    'LEKO_SINK_MODE':        '*snk*leko',
    'POWERAPP_SINK_MODE':    '*snk*powerapp',
    'FINDABLE_SINK_MODE':    '*snk*findable',
    'MILJOPROFIL_SINK_MODE': '*snk*miljoprofil',
    'DALUX_SINK_MODE':       '*snk*dalux',
}
for var, pattern in sink_groups.items():
    if env.get(var, 'running').lower() == 'paused':
        print(f"==> Excluding {var} group ({pattern})")
        for p in pattern.split():
            extra_args.extend(['--exclude', p])

# -- Smart Deployment Logic for Cloud Environments --
is_cloud_env = dbt_target in ['dev', 'test', 'prod']
has_manual_select = any(a.startswith('--select') or a == '-s' for a in extra_args)
force_all = '--all' in extra_args
use_smart_deploy = is_cloud_env and not has_manual_select and not force_all

is_dry_run = '--dry-run' in extra_args
if is_dry_run:
    extra_args = [a for a in extra_args if a != '--dry-run']

smart_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scripts', 'smart_deploy.py')

if use_smart_deploy or is_dry_run:
    print(f"==> Smart Deployment: Detecting changes for {dbt_target}...")
    # 1. Compile to refresh manifest.json
    subprocess.run([dbt_path, 'compile', '--target', dbt_target], env=env, check=True)

    if is_dry_run:
        # Show full report and exit without deploying
        subprocess.run([sys.executable, smart_script, dbt_target, 'report'], env=env)
        sys.exit(0)

    # 2. Identify modified/deleted models (stderr carries per-model reasons; stdout is the selection)
    find_proc = subprocess.run(
        [sys.executable, smart_script, dbt_target, 'find'],
        env=env, capture_output=True, text=True
    )
    if find_proc.stderr.strip():
        print(find_proc.stderr.rstrip())

    raw_output = find_proc.stdout.strip()
    if not raw_output:
        print("==> No changes detected. Skipping run.")
        sys.exit(0)

    to_run = []
    to_drop = []

    for item in raw_output.split():
        # Format: status:type:name
        parts = item.split(':')
        if len(parts) != 3:
            continue
        status, mat_type, name = parts
        
        if status == 'DELETED':
            to_drop.append((name, mat_type))
        else:
            to_run.append(name)

    if to_drop:
        print(f"==> Detected {len(to_drop)} deleted model(s). Dropping from RisingWave...")
        # Use dbt_target as default dbname if DBT_RW_DBNAME is not set
        rw_db = env.get('DBT_RW_DBNAME', dbt_target)
        psql_conn = f"host={env.get('DBT_RW_HOST', 'localhost')} port=4566 user={env.get('DBT_RW_USER', 'root')} dbname={rw_db} sslmode=require"
        psql_env = env.copy()
        psql_env['PGPASSWORD'] = env.get('DBT_RW_PASSWORD', '')

        for name, mat_type in to_drop:
            # Map dbt materialization to RisingWave DROP command
            if mat_type == 'sink':
                cmd = f'DROP SINK IF EXISTS public."{name}";'
            elif mat_type == 'materialized_view':
                cmd = f'DROP MATERIALIZED VIEW IF EXISTS public."{name}";'
            elif mat_type in ('table', 'table_with_connector'):
                cmd = f'DROP TABLE IF EXISTS public."{name}";'
            else:
                # Default fallback (try view)
                cmd = f'DROP VIEW IF EXISTS public."{name}";'
            
            print(f"  Dropping {mat_type}: {name}")
            subprocess.run(['psql', psql_conn, '-c', cmd], env=psql_env, capture_output=True)

    if not to_run:
        print("==> No models to run (only deletions). Done.")
        # We still need to update state to save that these are gone
        subprocess.run([sys.executable, smart_script, dbt_target, 'update'], env=env, check=True)
        sys.exit(0)

    selection = ' '.join([n + '+' for n in to_run])
    print(f"==> Deploying {len(to_run)} changed model(s) with downstream (+).")
    extra_args.extend(['--select', selection, '--full-refresh'])
elif force_all:
    extra_args = [a for a in extra_args if a != '--all']

if run_seed:
    seed_result = subprocess.run(
        [dbt_path, 'seed', '--target', dbt_target],
        env=env
    )
    if seed_result.returncode != 0:
        sys.exit(seed_result.returncode)

result = subprocess.run(
    [dbt_path, 'run', '--target', dbt_target] + extra_args,
    env=env
)

if use_smart_deploy or force_all:
    # Always update state, even after a partial failure — smart_deploy.py's
    # `update` reads target/run_results.json and only marks models with
    # status=success as deployed. Models that errored or were skipped (due to
    # an upstream failure) keep their old state so the next deploy retries
    # only them, instead of either silently skipping them forever or
    # re-running the whole batch (including models that already succeeded).
    subprocess.run([sys.executable, smart_script, dbt_target, 'update'], env=env, check=True)

sys.exit(result.returncode)
PYEOF

# ── Apply sink modes (PAUSE/RESUME) ──────────────────────────────────────────
echo "==> Applying sink modes ..."
"$PYTHON" scripts/apply_sink_modes.py "$W_RESOLVED_ENV" "$DBT_TARGET" "$USE_PORT_FORWARD"

# ── Deploy parallel sink views (v_snk_*) ─────────────────────────────────────
echo "==> Deploying parallel queryable sink views (v_snk_*) ..."
"$PYTHON" scripts/deploy_sink_views.py "$W_RESOLVED_ENV" "$DBT_TARGET" "$USE_PORT_FORWARD"

# ── State Sync (Upload to GCS) ───────────────────────────────────────────────
if [ -z "${STATE_BUCKET:-}" ]; then
    _gcs=$(grep '^GCS_BIGQUERY_STAGING_BUCKET=' "$RESOLVED_ENV" 2>/dev/null | cut -d= -f2- || true)
    [ -n "$_gcs" ] && STATE_BUCKET="${_gcs}/dbt-state"
fi
if [ -n "${STATE_BUCKET:-}" ] && [ -f "state/manifest_$ENV.json" ]; then
    echo "==> Syncing state to gs://$STATE_BUCKET/manifest_$ENV.json ..."
    gsutil cp "state/manifest_$ENV.json" "gs://$STATE_BUCKET/manifest_$ENV.json"
fi
