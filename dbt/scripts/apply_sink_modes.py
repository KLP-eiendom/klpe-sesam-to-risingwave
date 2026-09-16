"""
apply_sink_modes.py — Apply PAUSE/RESUME to RisingWave sinks based on env vars.

Usage:
    python apply_sink_modes.py <env_file> <dbt_target> <use_port_forward>

Called by deploy.sh after every dbt run. Idempotent.

Env vars (in .env.*):
    FORVALTER_SINK_MODE=paused|running   (default: running)
    KUNDEPORTAL_SINK_MODE=paused|running
    SUPEROFFICE_SINK_MODE=paused|running
    BQ_SINK_MODE=paused|running
    LEKO_SINK_MODE=paused|running
    POWERAPP_SINK_MODE=paused|running
    FINDABLE_SINK_MODE=paused|running
    MILJOPROFIL_SINK_MODE=paused|running
"""

import os
import sys

import psycopg2

SINK_GROUPS: dict = {
    'FORVALTER_SINK_MODE':   lambda n: n.endswith('_forvalter'),
    'KUNDEPORTAL_SINK_MODE': lambda n: n.endswith('_kundeportal'),
    'SUPEROFFICE_SINK_MODE': lambda n: n.endswith('_superoffice'),
    'BQ_SINK_MODE':          lambda n: n.endswith('_bq') or n.endswith('_bqeos'),
    'LEKO_SINK_MODE':        lambda n: n.endswith('_leko') or '_leko_' in n,
    'POWERAPP_SINK_MODE':    lambda n: n.endswith('_powerapp'),
    'FINDABLE_SINK_MODE':    lambda n: n.endswith('_findable'),
    'MILJOPROFIL_SINK_MODE': lambda n: n.endswith('_miljoprofil'),
    'DALUX_SINK_MODE':       lambda n: n.endswith('_dalux') or '_dalux_' in n,
}


def get_group_for_sink(sink_name: str):
    for group, matcher in SINK_GROUPS.items():
        if matcher(sink_name):
            return group
    return None


def get_desired_mode(group, env_vars: dict) -> str:
    if group is None:
        return 'running'
    return env_vars.get(group, 'running').lower()


def load_env_file(env_file: str) -> dict:
    env = {}
    if not env_file or not os.path.exists(env_file):
        return env
    with open(env_file) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, _, value = line.partition('=')
            env[key.strip()] = value.strip()
    return env


def get_rw_version(conn) -> float:
    """Return the RisingWave version as a float (e.g. 1.7)."""
    with conn.cursor() as cur:
        cur.execute("SELECT version()")
        version_str = cur.fetchone()[0]
        # Format is usually: PostgreSQL 13.14.0-RisingWave-2.7.2 (...)
        import re
        match = re.search(r'RisingWave-(\d+\.\d+)', version_str)
        if match:
            return float(match.group(1))
    return 0.0


def apply_modes(conn, env_vars: dict) -> None:
    version = get_rw_version(conn)
    if version < 1.7:
        print(f"==> Skipping sink modes: RisingWave v{version} < 1.7 (PAUSE/RESUME not supported).")
        return

    with conn.cursor() as cur:
        cur.execute('SELECT name FROM rw_catalog.rw_sinks')
        sinks = [row[0] for row in cur.fetchall()]

    for sink_name in sinks:
        group = get_group_for_sink(sink_name)
        mode = get_desired_mode(group, env_vars)
        action = 'PAUSE' if mode == 'paused' else 'RESUME'
        label = f'[{group}]' if group else '[no group → running]'
        
        try:
            with conn.cursor() as cur:
                cur.execute(f'ALTER SINK "{sink_name}" {action}')
            conn.commit()
            print(f'  {action:6s}  {sink_name}  {label}')
        except Exception as e:
            conn.rollback()
            if "parser error" in str(e).lower():
                print(f"==> Skipping sink modes: Syntax '{action}' not supported by this RisingWave version.")
                return # Exit early, no point in trying the others
            print(f'    WARNING: Could not apply {action} to {sink_name}: {e}')


def main() -> None:
    if len(sys.argv) < 4:
        print('Usage: apply_sink_modes.py <env_file> <dbt_target> <use_port_forward>', file=sys.stderr)
        sys.exit(1)

    env_file         = sys.argv[1]
    dbt_target       = sys.argv[2]
    use_port_forward = sys.argv[3] == 'true'

    env_vars = load_env_file(env_file)

    if dbt_target in ('localdev', 'ci'):
        print('==> Skipping sink modes (localdev/ci target).')
        return

    if use_port_forward:
        host, user, password, port = 'localhost', 'root', '', 4566
    else:
        host     = env_vars.get('DBT_RW_HOST', 'localhost')
        user     = env_vars.get('DBT_RW_USER', 'root')
        password = env_vars.get('DBT_RW_PASSWORD', '')
        port     = int(env_vars.get('DBT_RW_PORT', '4566'))

    try:
        conn = psycopg2.connect(host=host, port=port, user=user, password=password, dbname='dev')
        apply_modes(conn, env_vars)
        conn.close()
    except Exception as exc:
        print(f'WARNING: apply_sink_modes failed: {exc}', file=sys.stderr)
        print('WARNING: Continuing deploy — sinks may not be in correct mode.', file=sys.stderr)


if __name__ == '__main__':
    main()
