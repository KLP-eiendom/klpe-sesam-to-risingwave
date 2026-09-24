import json
import os
import re
from pathlib import Path
import shutil
import sys

# Paths
SESAM_EXPECTED = Path("sesam_expected")
RW_EXPECTED = Path(__file__).resolve().parent.parent / "models" / "sinks" / "unit_tests" / "expected_data"
SINKS_DIR = Path(__file__).resolve().parent.parent / "models" / "sinks"

def get_mart_ref(sql_path):
    content = sql_path.read_text(encoding="utf-8")
    # Matches {{ ref('foo') }} or ref('foo')
    m = re.search(r"ref\('([^']+)'\)", content)
    return m.group(1) if m else None

def sync():
    if not SESAM_EXPECTED.exists():
        print(f"ERROR: Sesam expected directory not found: {SESAM_EXPECTED}")
        return

    RW_EXPECTED.mkdir(parents=True, exist_ok=True)
    count = 0
    
    # Pre-calculate sesam list for fuzzy matching if needed
    sesam_files = [f.stem for f in SESAM_EXPECTED.glob("*.json") if not f.name.endswith(".test.json")]
    
    for sink_sql in sorted(SINKS_DIR.glob("snk_*.sql")):
        sink_name = sink_sql.stem
        
        # 1. Determine Sesam base name mapping
        # Examples:
        # snk_bygg_bqeos -> bygg-bqeos-rest-endpoint
        # snk_energyconsumption_kundeportal -> energyconsumption-kundeportal-endpoint
        
        base_parts = sink_name.replace("snk_", "").split("_")
        base_name_dash = "-".join(base_parts)
        
        # Priority mapping
        candidates = [
            f"{base_name_dash}-endpoint",
            f"{base_name_dash}-rest-endpoint",
            base_name_dash,
            # Special case for some misnamed ones
            f"{base_parts[0]}-{base_parts[1]}-rest-endpoint" if len(base_parts) > 2 else None,
            # Or direct match if parts are reversed
            "-".join(reversed(base_parts)) + "-endpoint"
        ]
        candidates = [c for c in candidates if c]
        
        found_base = None
        for cand in candidates:
            if (SESAM_EXPECTED / f"{cand}.json").exists():
                found_base = cand
                break
        
        # 2. If still not found, try substring match (fuzzy)
        if not found_base:
            for sf in sesam_files:
                if all(p in sf for p in base_parts):
                    found_base = sf
                    break
        
        if not found_base:
            print(f"  [SKIP] {sink_name}: No matching Sesam file found in {SESAM_EXPECTED}")
            continue
            
        # 3. Copy/Rename Data JSON
        shutil.copy(SESAM_EXPECTED / f"{found_base}.json", RW_EXPECTED / f"{sink_name}.json")
        
        # 4. Create/Repair Metadata Test JSON
        meta_src_path = SESAM_EXPECTED / f"{found_base}.test.json"
        mart = get_mart_ref(sink_sql)
        
        # Use existing Sesam metadata as base if it exists
        meta_content = {}
        if meta_src_path.exists():
            try:
                meta_content = json.loads(meta_src_path.read_text(encoding="utf-8"))
            except Exception as e:
                print(f"  [WARN] {sink_name}: Failed to read Sesam metadata {meta_src_path}: {e}")
        
        # Override/Inject mart key
        if mart:
            meta_content["mart"] = mart
        else:
            print(f"  [WARN] {sink_name}: No ref() found in SQL, 'mart' key will be missing.")
            
        # Ensure blacklist exists (even if empty) or keep existing
        if "blacklist" not in meta_content:
            meta_content["blacklist"] = ["Created", "LastUpdated"] # Default sensible blacklist
            
        (RW_EXPECTED / f"{sink_name}.test.json").write_text(
            json.dumps(meta_content, indent=2, ensure_ascii=False),
            encoding="utf-8"
        )
        
        print(f"  [OK] {sink_name} synced from {found_base} (mart: {mart})")
        count += 1
        
    print(f"\nSUCCESS: Synced {count} test data pairs to {RW_EXPECTED}")

if __name__ == "__main__":
    sync()
