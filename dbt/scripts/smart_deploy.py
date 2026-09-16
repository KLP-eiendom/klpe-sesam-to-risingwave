import hashlib
import json
import os
import sys

SINK_GROUPS = {
    'FORVALTER_SINK_MODE':   lambda n: n.endswith('_forvalter'),
    'KUNDEPORTAL_SINK_MODE': lambda n: n.endswith('_kundeportal'),
    'SUPEROFFICE_SINK_MODE': lambda n: n.endswith('_superoffice'),
    'BQ_SINK_MODE':          lambda n: n.endswith('_bq') or n.endswith('_bqeos'),
    'LEKO_SINK_MODE':        lambda n: n.endswith('_leko') or '_leko_' in n,
    'POWERAPP_SINK_MODE':    lambda n: n.endswith('_powerapp'),
    'FINDABLE_SINK_MODE':    lambda n: n.endswith('_findable'),
    'MILJOPROFIL_SINK_MODE': lambda n: n.endswith('_miljoprofil'),
}

def compute_normalized_checksum(file_path: str):
    """Computes SHA256 of file content normalized to LF (\n) and stripped of trailing whitespace.
    Guarantees OS-independent line ending immunity (Windows CRLF vs Linux LF).
    """
    if not file_path or not os.path.exists(file_path):
        return None
    try:
        with open(file_path, 'rb') as f:
            content = f.read()
        normalized = content.replace(b'\r\n', b'\n').strip()
        return hashlib.sha256(normalized).hexdigest()
    except Exception:
        return None

def get_group_for_sink(sink_name: str):
    for group, matcher in SINK_GROUPS.items():
        if matcher(sink_name):
            return group
    return None

def get_current_manifest(target_path='target/manifest.json'):
    if not os.path.exists(target_path):
        return None
    with open(target_path) as f:
        return json.load(f)

def get_last_state(state_file):
    if os.path.exists(state_file):
        with open(state_file) as f:
            return json.load(f)
    return {}

def save_state(state_file, state):
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

def classify_models(manifest, last_state):
    """Returns list of (node_id, name, original_file_path, status, type) sorted by name.
    status is one of: 'NEW', 'CHANGED', 'DELETED', 'unchanged'
    """
    project_name = manifest['metadata'].get('project_name', 'kdi_risingwave')
    rows = []
    current_node_ids = set()

    # Get current and last sink modes to detect transitions from paused -> running
    current_modes = {var: os.environ.get(var, 'running').lower() for var in SINK_GROUPS}
    last_metadata = last_state.get('_metadata', {})
    last_modes = last_metadata.get('sink_modes', {})

    script_dir = os.path.dirname(os.path.abspath(__file__))
    dbt_root = os.path.dirname(script_dir)

    # 1. Process current models in manifest
    for node_id, node in manifest['nodes'].items():
        if node['resource_type'] != 'model' or node['package_name'] != project_name:
            continue
        checksum = node.get('checksum', {}).get('checksum')
        if not checksum:
            continue
        
        current_node_ids.add(node_id)
        name = node['name']
        path = node.get('original_file_path', node.get('path', ''))
        mat_type = node.get('config', {}).get('materialized', 'view')

        # Compute normalized LF checksum directly from file on disk for OS immunity
        abs_path = os.path.join(dbt_root, path) if path else None
        norm_checksum = compute_normalized_checksum(abs_path)

        # Detect transition from paused -> running
        group = get_group_for_sink(name)
        group_resumed = False
        if mat_type == 'sink' and group:
            last_mode = last_modes.get(group, 'running').lower()
            current_mode = current_modes.get(group, 'running').lower()
            if last_mode == 'paused' and current_mode == 'running':
                group_resumed = True
                print(f"  DEBUG: {name} group {group} was resumed (paused -> running). Forcing deploy.", file=sys.stderr)

        # Handle both old state (string checksum) and new state (dict)
        last_entry = last_state.get(node_id)
        last_checksum = last_entry if isinstance(last_entry, str) else (last_entry.get('checksum') if last_entry else None)

        if not last_checksum:
            status = 'NEW'
        elif group_resumed:
            status = 'CHANGED'
        elif last_checksum == checksum or (norm_checksum and last_checksum == norm_checksum):
            status = 'unchanged'
        else:
            status = 'CHANGED'
            print(f"  DEBUG: {name} hash mismatch! state: {last_checksum[:8]}... target: {(norm_checksum or checksum)[:8]}...", file=sys.stderr)
        
        rows.append((node_id, name, path, status, mat_type))

    # 2. Identify deleted models (present in state but not in manifest)
    for node_id, last_entry in last_state.items():
        if node_id == '_metadata':
            continue
        if node_id not in current_node_ids:
            # We only know name/type if we used the new state format
            name = last_entry.get('name', node_id.split('.')[-1]) if isinstance(last_entry, dict) else node_id.split('.')[-1]
            mat_type = last_entry.get('type', 'unknown') if isinstance(last_entry, dict) else 'unknown'
            rows.append((node_id, name, '[DELETED]', 'DELETED', mat_type))

    rows.sort(key=lambda r: r[1])
    return rows

def main():
    if len(sys.argv) < 3:
        print("Usage: python smart_deploy.py <env> <command: find|update|report>")
        sys.exit(1)

    env = sys.argv[1]
    command = sys.argv[2]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    state_dir = os.path.join(os.path.dirname(script_dir), 'state')
    state_file = os.path.join(state_dir, f'manifest_{env}.json')
    target_path = os.path.join(os.path.dirname(script_dir), 'target', 'manifest.json')

    if command == 'find':
        manifest = get_current_manifest(target_path)
        if not manifest:
            sys.exit(0)

        last_state = get_last_state(state_file)
        rows = classify_models(manifest, last_state)

        modified = [r for r in rows if r[3] != 'unchanged']
        if not modified:
            sys.exit(0)

        # Output to stdout (consumed by deploy.sh)
        # Format: status:type:name (e.g. CHANGED:sink:snk_foo DELETED:materialized_view:mrt_bar)
        print(' '.join([f"{r[3]}:{r[4]}:{r[1]}" for r in modified]))

        # Log reason per model to stderr so caller can display it
        for _, name, path, status, _ in modified:
            print(f"  {status:<10} {name}  ({path})", file=sys.stderr)

    elif command == 'update':
        manifest = get_current_manifest(target_path)
        if not manifest:
            sys.exit(1)

        # Only mark models as deployed if we can prove they actually succeeded —
        # a partially-failed `dbt run` (some models error, some skip due to an
        # upstream failure) must not mark the whole selected batch as up to date,
        # or the next deploy would silently skip re-running the ones that failed
        # AND never re-run the ones that succeeded, since both look "unchanged".
        run_results_path = os.path.join(os.path.dirname(script_dir), 'target', 'run_results.json')
        if not os.path.exists(run_results_path):
            print("  WARNING: no target/run_results.json found — cannot tell which models "
                  "actually ran. Skipping state update (state left as-is).", file=sys.stderr)
            sys.exit(0)

        with open(run_results_path) as f:
            run_results = json.load(f)
        failed_ids = {
            r.get('unique_id') for r in run_results.get('results', [])
            if r.get('status') not in ('success', 'pass')
        }
        if failed_ids:
            print(f"  Not marking {len(failed_ids)} failed/skipped model(s) as deployed — "
                  f"they'll be retried on the next deploy.", file=sys.stderr)

        last_state = get_last_state(state_file)
        new_state = {}
        for node_id, node in manifest['nodes'].items():
            if node['resource_type'] != 'model':
                continue
            if node_id in failed_ids:
                # Preserve whatever state existed before this run so the next
                # `find` still classifies this model as changed and retries it.
                if node_id in last_state:
                    new_state[node_id] = last_state[node_id]
                continue
            path = node.get('original_file_path', node.get('path', ''))
            abs_path = os.path.join(os.path.dirname(script_dir), path) if path else None
            checksum = compute_normalized_checksum(abs_path) or node.get('checksum', {}).get('checksum')
            if checksum:
                new_state[node_id] = {
                    'checksum': checksum,
                    'name': node['name'],
                    'type': node.get('config', {}).get('materialized', 'view')
                }

        # Store current sink modes in metadata
        new_state['_metadata'] = {
            'sink_modes': {var: os.environ.get(var, 'running').lower() for var in SINK_GROUPS}
        }

        save_state(state_file, new_state)
        print(f"Updated state for {env} ({len(new_state) - 1} models + metadata)")

    elif command == 'report':
        manifest = get_current_manifest(target_path)
        if not manifest:
            print("ERROR: No manifest found. Run `dbt compile` first.", file=sys.stderr)
            sys.exit(1)

        last_state = get_last_state(state_file)
        state_label = f"state/{os.path.basename(state_file)}"
        has_state = bool(last_state)

        rows = classify_models(manifest, last_state)
        changed = [r for r in rows if r[3] != 'unchanged']
        unchanged = [r for r in rows if r[3] == 'unchanged']

        col = 52
        print()
        print(f"  Smart deploy report — {env}")
        print(f"  State file : {state_label} ({'loaded, ' + str(len(last_state)) + ' entries' if has_state else 'NOT FOUND — all models are NEW'})")
        print()
        print(f"  {'Model':<{col}} {'Status':<12} File")
        print('  ' + '-' * (col + 50))
        for _, name, path, status, _ in changed:
            print(f"  {name:<{col}} {status:<12} {path}")
        if changed and unchanged:
            print()
        for _, name, path, status, _ in unchanged:
            print(f"  {name:<{col}} {status:<12} {path}")
        print()
        print(f"  Summary: {len(changed)} would process ({sum(1 for r in changed if r[3]=='NEW')} new, "
              f"{sum(1 for r in changed if r[3]=='CHANGED')} changed, "
              f"{sum(1 for r in changed if r[3]=='DELETED')} deleted), "
              f"{len(unchanged)} unchanged / skipped")
        print()

if __name__ == "__main__":
    main()
