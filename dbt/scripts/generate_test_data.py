#!/usr/bin/env python3
"""
Generate seeds/test_data/stg_*.json from KdiSesam pipe test entities.

Reads source.alternatives.test.entities from KdiSesam pipe configs and writes
them into the seeds/test_data/ directory so load_test_data.py can insert them
into a local RisingWave instance.

Rules:
  - Skips axapta-* pipes (not in RisingWave scope)
  - Skips CDC tables (WHERE FALSE views in localdev) — no data to insert
  - Webhook tables (payload JSONB): writes entities as-is with table_type=webhook
  - Poller tables: computes _id from IdExpression, writes entities with _id

Usage:
  python3 scripts/generate_test_data.py
  python3 scripts/generate_test_data.py --dry-run   # print summary only

The KdiSesam directory is auto-detected from the sibling ../KdiSesam path.
Override with KDISESAM_DIR environment variable.
"""

import json
import os
import re
import sys
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
DBT_DIR = SCRIPT_DIR.parent
STAGING_DIR = DBT_DIR / "models" / "staging"
OUTPUT_DIR = DBT_DIR / "seeds" / "test_data"

DEFAULT_SESAM_DIR = Path("../KdiSesam")
SESAM_PIPES_DIR = Path(os.environ.get("KDISESAM_DIR", str(DEFAULT_SESAM_DIR))) / "src" / "node" / "pipes"

# ── Pipe -> staging table overrides ────────────────────────────────────────────
# Used when the simple rule (hyphen->underscore, prefix stg_) doesn't apply.

PIPE_TABLE_OVERRIDES = {
    "camunda-processinstance": "stg_camunda_act_hi_procinst",
    "camunda-taskinstance":    "stg_camunda_act_hi_taskinst",
    "superoffice-saleSimple":  "stg_superoffice_salesimple",
}

# Pipes with no corresponding RisingWave staging table — skip entirely.
PIPE_SKIP = {
    "d365-map",
    "forvalter-prosjektsortedusertask",  # maps to eiendom poller table (different system)
    "vault-secrets",
    "superoffice-personinterest",
}

# ── IdExpression lookup ────────────────────────────────────────────────────────
# Built from all poller appsettings. Key = staging table name.

def build_id_map() -> dict:
    """Read all poller appsettings and return {table: {'expr': str, 'pks': list}}."""
    id_map = {}
    repo_root = DBT_DIR.parent
    pollers = [
        (repo_root / "src/cloud-run/bigquery-entity-poller/appsettings.json",
         lambda d: d.get("BigQuerySettings", {}).get("Tables", [])),
        (repo_root / "src/cloud-run/superoffice-entity-poller/appsettings.json",
         lambda d: d.get("KdiApiSettings", {}).get("Entities", [])),
        (repo_root / "src/cloud-run/fdvweb-entity-poller/appsettings.json",
         lambda d: d.get("FdvwebApiSettings", {}).get("Entities", [])),
        (repo_root / "src/cloud-run/eiendom-entity-poller/appsettings.json",
         lambda d: d.get("EiendomApiSettings", {}).get("Entities", [])),
    ]
    for path, extractor in pollers:
        try:
            d = json.loads(path.read_text(encoding="utf-8"))
            for entry in extractor(d):
                tbl = entry.get("TargetTable", "")
                if tbl:
                    id_map[tbl] = {
                        "expr": entry.get("IdExpression", ""),
                        "pks":  entry.get("PrimaryKeyColumns", []),
                    }
        except Exception:
            pass
    return id_map


# ── IdExpression evaluator ────────────────────────────────────────────────────

def _split_args(s: str) -> list:
    """Split comma-separated function args, respecting nested parens and quoted strings."""
    depth = 0
    in_quote = False
    current = []
    result = []
    for char in s:
        if char == '"' and not in_quote:
            in_quote = True
            current.append(char)
        elif char == '"' and in_quote:
            in_quote = False
            current.append(char)
        elif in_quote:
            current.append(char)
        elif char == '(':
            depth += 1
            current.append(char)
        elif char == ')':
            depth -= 1
            current.append(char)
        elif char == ',' and depth == 0:
            result.append(''.join(current).strip())
            current = []
        else:
            current.append(char)
    if current:
        result.append(''.join(current).strip())
    return result


def eval_expr(expr: str, entity: dict):
    """Evaluate a simple IdExpression string against an entity dict."""
    expr = expr.strip()
    if not expr:
        return None

    # String literal: "value"
    if expr.startswith('"') and expr.endswith('"') and len(expr) >= 2:
        return expr[1:-1]

    # Numeric literal
    if re.match(r'^-?\d+(\.\d+)?$', expr):
        return expr

    # Function call: name(args...)
    m = re.match(r'^(\w+)\((.+)\)$', expr, re.DOTALL)
    if m:
        func = m.group(1).lower()
        raw_args = m.group(2)
        args = _split_args(raw_args)

        if func == "concat":
            parts = []
            for a in args:
                v = eval_expr(a, entity)
                parts.append("" if v is None else str(v))
            return "".join(parts)

        if func == "coalesce":
            for a in args:
                v = eval_expr(a, entity)
                if v is not None and v != "":
                    return v
            return None

        if func == "string":
            v = eval_expr(args[0], entity)
            return str(v) if v is not None else None

        if func == "lower":
            v = eval_expr(args[0], entity)
            return v.lower() if isinstance(v, str) else v

        if func == "upper":
            v = eval_expr(args[0], entity)
            return v.upper() if isinstance(v, str) else v

        if func == "date":
            v = eval_expr(args[0], entity)
            return str(v)[:10] if v is not None else None

        # Unknown function — return None
        return None

    # Field name — case-sensitive lookup first, then case-insensitive
    if expr in entity:
        return entity[expr]
    lower_expr = expr.lower()
    for k, v in entity.items():
        if k.lower() == lower_expr:
            return v
    return None


def compute_id(entity: dict, id_info: dict, table: str, idx: int) -> str:
    """Compute _id for an entity using IdExpression or PrimaryKeyColumns."""
    expr = id_info.get("expr", "")
    pks = id_info.get("pks", [])

    if expr:
        val = eval_expr(expr, entity)
        if val is not None:
            return str(val)

    if pks:
        parts = []
        for pk in pks:
            v = entity.get(pk)
            if v is None:
                # Try case-insensitive
                for k, kv in entity.items():
                    if k.lower() == pk.lower():
                        v = kv
                        break
            parts.append("" if v is None else str(v))
        if any(parts):
            return "-".join(parts)

    # Fallback: sequential id
    return f"{table}-{idx + 1}"


# ── Staging SQL helpers ────────────────────────────────────────────────────────

def staging_sql_content(table_name: str) -> str:
    path = STAGING_DIR / f"{table_name}.sql"
    return path.read_text(encoding="utf-8") if path.exists() else ""


def is_cdc_table(table_name: str) -> bool:
    return "WHERE FALSE" in staging_sql_content(table_name)


def is_webhook_table(table_name: str) -> bool:
    return "payload JSONB" in staging_sql_content(table_name)


# ── Pipe processing ───────────────────────────────────────────────────────────

def pipe_name_to_table(pipe_name: str) -> str:
    """Derive the staging table name from a Sesam pipe name."""
    if pipe_name in PIPE_TABLE_OVERRIDES:
        return PIPE_TABLE_OVERRIDES[pipe_name]
    return "stg_" + pipe_name.replace("-", "_").lower()


def load_sesam_entities(pipe_path: Path) -> list:
    """Extract test entities from source.alternatives.test.entities."""
    try:
        d = json.loads(pipe_path.read_text(encoding="utf-8"))
        alts = d.get("source", {}).get("alternatives", {})
        if not isinstance(alts, dict):
            return []
        test_src = alts.get("test", {})
        if not isinstance(test_src, dict):
            return []
        entities = test_src.get("entities", [])
        return entities if isinstance(entities, list) else []
    except Exception:
        return []


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    dry_run = "--dry-run" in sys.argv

    if not SESAM_PIPES_DIR.exists():
        print(f"ERROR: KdiSesam pipes dir not found: {SESAM_PIPES_DIR}", file=sys.stderr)
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    id_map = build_id_map()

    pipe_files = sorted(SESAM_PIPES_DIR.glob("*.conf.json"))
    generated = []
    skipped = []

    for pipe_path in pipe_files:
        pipe_name = pipe_path.stem.replace(".conf", "")

        # Skip axapta pipes (user instruction)
        if pipe_name.startswith("axapta"):
            continue

        # Skip explicitly listed pipes
        if pipe_name in PIPE_SKIP:
            skipped.append((pipe_name, "explicitly skipped"))
            continue

        # Skip forvalter-* and kundeportal-* (CDC views in localdev)
        # We still need to derive the table name to check, but let's be direct
        if pipe_name.startswith("forvalter-") or pipe_name.startswith("kundeportal-"):
            skipped.append((pipe_name, "CDC table (view in localdev)"))
            continue

        entities = load_sesam_entities(pipe_path)
        if not entities:
            continue  # No test entities in this pipe

        table_name = pipe_name_to_table(pipe_name)

        # Check if staging table exists
        if not (STAGING_DIR / f"{table_name}.sql").exists():
            skipped.append((pipe_name, f"no staging model {table_name}.sql"))
            continue

        # Skip CDC tables
        if is_cdc_table(table_name):
            skipped.append((pipe_name, f"{table_name} is CDC/view — skipped"))
            continue

        webhook = is_webhook_table(table_name)
        id_info = id_map.get(table_name, {"expr": "", "pks": []})

        if not webhook:
            # Poller table: ensure each entity has _id
            enriched = []
            for idx, entity in enumerate(entities):
                e = dict(entity)
                if "_id" not in e or e["_id"] is None:
                    e["_id"] = compute_id(entity, id_info, table_name, idx)
                else:
                    e["_id"] = str(e["_id"])
                # Move _id to first position
                ordered = {"_id": e.pop("_id")}
                ordered.update(e)
                enriched.append(ordered)
            output = {"entities": enriched}
        else:
            # Webhook table: entities as-is
            output = {"entities": entities, "table_type": "webhook"}

        out_path = OUTPUT_DIR / f"{table_name}.json"

        if dry_run:
            print(f"  [DRY] {pipe_name} -> {table_name} ({len(entities)} entities, {'webhook' if webhook else 'poller'})")
        else:
            out_path.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
            print(f"  {pipe_name} -> {table_name}.json ({len(entities)} entities, {'webhook' if webhook else 'poller'})")

        generated.append(table_name)

    print(f"\nGenerated {len(generated)} test data files.")
    if skipped:
        print(f"Skipped {len(skipped)} pipes:")
        for name, reason in skipped:
            print(f"  - {name}: {reason}")


if __name__ == "__main__":
    main()
