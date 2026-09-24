---
name: risingwave-migration
description: >
  Domain knowledge for the KdiRisingWave project — migrating KLP Eiendom from
  Sesam.io to RisingWave streaming database. Use when working with dbt models,
  CDC sources, sinks, Sesam→RisingWave mappings, or Cloud Run pollers in this
  codebase.
---

# KdiRisingWave — Migration Domain Knowledge

This project replaces Sesam.io with RisingWave as the integration hub for KLP Eiendom.
Data flows: source systems → RisingWave (staging + marts) → target systems (Forvalter, Kundeportal, Miljoprofil, BigQuery, SuperOffice via PubSub).

All RisingWave DDL is managed by dbt. See `CLAUDE.md` for full patterns and `README.md` for architecture.

## Quick Reference

### Deploy

```bash
cd dbt
./deploy.sh              # all models → dev
./deploy.sh prod         # all models → prod
./deploy.sh dev --select stg_superoffice_ticket
./deploy.sh dev --exclude tag:sink
```

### Test locally

```bash
cd dbt && bash run-test.sh   # docker compose + dbt seed + dbt run (excl. sinks + CDC sources)
# Expected: PASS=87 WARN=0 ERROR=0
```

### Dev tool setup (one-time)

```bash
pip install dbt-osmosis sqlfluff sqlfluff-templater-dbt
```

- **dbt-osmosis** — auto-generates/updates `schema.yml` column docs from SQL models
- **sqlfluff** — SQL linter/formatter with Jinja2/dbt template support; config in `dbt/.sqlfluff`

### Unit tests

```bash
cd dbt
# Run all 53 unit tests (no live RisingWave needed)
FORVALTER_MYSQL_DB=x KUNDEPORTAL_MYSQL_DB=x MILJOPROFIL_MYSQL_DB=x RW_WEBHOOK_SECRET=x dbt test --target dev

# Run a single model's tests
FORVALTER_MYSQL_DB=x KUNDEPORTAL_MYSQL_DB=x MILJOPROFIL_MYSQL_DB=x RW_WEBHOOK_SECRET=x dbt test --select mrt_kredittvurdering_superoffice --target dev
```

**Covered marts** (non-global, endpoint-facing — derived from Sesam `source.alternatives.test.entities`):
`mrt_bisnode_leverandor`, `mrt_kredittvurdering_superoffice`, `mrt_leverandorvurdering_superoffice`,
`mrt_leverandor_omsetning_superoffice`, `mrt_d365_kunde_kontrakt_leie`, `mrt_global_invoice`,
`mrt_fdvweb_energy_categorization`, `mrt_superoffice_ticket`, `mrt_superoffice_user`,
`mrt_verified_document`, `mrt_verified_personkonvolutt`, `mrt_lekoworker_directlink`

Sink-level tests (39 tests across 14 files) cover all major sink column mappings in `models/sinks/unit_tests/`.

`mrt_global_*` marts are intentionally excluded — they are intermediate merge layers with no direct Sesam test equivalent.

### Sink count validation (Sesam ↔ RisingWave)

Read-only count comparison per sink, for migration cutover. Reports RW mart vs RW sink vs Sesam.

```bash
cd dbt
dbt compile --select tag:sink --target test          # 1. compile sink SELECTs (read-only)
python scripts/verify_sink_counts.py test            # 2. all sinks → verify_sink_counts_test.json (+ .log)
python scripts/verify_sink_counts.py test --select snk_bygg_forvalter
```

- Reads **RW mart** (FROM relation, no WHERE) + **RW sink** (compiled SELECT) + **Sesam source** dataset count; status = mart-vs-Sesam.
- Sesam `*-endpoint` pipes are NOT readable (503) → read the pipe's `source.dataset`; map in `scripts/sink_sesam_map.json` (regenerate from pipe configs when pipes change). Non-deleted = Sesam `count-index-exists`.
- Vault (case-sensitive): RW creds `kv/risingwave/<env>` (lowercase r — owns the marts), Sesam `kv/kdi/<env>` (`SesamAccessInfo:AuthToken`, `:SesamBaseUrl`). RW is RisingWave Cloud — direct connect, no port-forward.
- `prod` needs `--confirm-prod`. Counts only (Tier 1) — for values, see Tier 2 below. Full notes: `memory/project_sink_count_validation.md`, plan in `.claude/plans/`.

### Sink value validation — Tier 2 (`verify_sink_values.py`)

**Strict ID parity** + value comparison per sink. The migration requires IDs to be **identical** between Sesam and RisingWave, so rows match **only** on the sink's `id_field` — the tool never normalizes/strips/transforms keys. An ID that doesn't line up is `ID_MISMATCH`, **fixed in the RisingWave sink** (so it emits the ID Sesam wrote), never worked around. Matched rows are then field-diffed. Reuses `verify_e2e.py`'s engine + Tier-1 bootstrap/map.

```bash
cd dbt
dbt compile --select tag:sink --target test
python scripts/verify_sink_values.py test            # all sinks → _summary.csv + _diffs.csv + .json   (add --id-mismatches for _id_mismatches.csv)
python scripts/verify_sink_values.py test --select snk_firma_forvalter
```

- **Outputs**: `_summary.csv` (one row/sink: `criticality, sink, status, …, matched, rw_only, sesam_only, …, detail`), `_id_mismatches.csv` (**opt-in** `--id-mismatches`, off by default — large; the fix-RW worklist — `sink, id, side`=rw_only|sesam_only), `_diffs.csv` (field mismatch in matched rows: `sink,id,field,rw_value,sesam_value`), `.json`. UTF-8-BOM + `;` delimiter (`--csv-delimiter ,`). Sorted by ascending criticality (`STATUS_RANK`).
- **Statuses**: `PARITY` (ids + values equal) · `DIFFERENCES` (ids match, values differ) · `ID_MISMATCH` (rw_only/sesam_only ids — fix RW) · `NO_ID_FIELD` (no id_field, or not a real output col) · `SESAM_MISSING/DOWN/EMPTY` · `RW_EMPTY` · `SKIPPED_LARGE` (> `--max-rows`) · `NO_SESAM_SOURCE` (Findable, intentional) · `ERROR`.
- **Consumption exception**: the 8 `*consumption_*` sinks were re-keyed (Sesam composite PK → RW synthetic `UniqueId`); their `id_field` is the **business composite** (`[ByggNummer,Type,Unit,Mnd]`, +`KundeNummer` for customer, `[ByggNummer,TypeKode,Mnd]` for waste) with `UniqueId` blacklisted.
- **CANDIDATE caveat**: rw_only/sesam_only ids are candidates — we read the Sesam *source* (input, keeps `<ns>:` prefixes) since the endpoint *output* (de-namespaced) isn't API-readable; verify against the real destination before changing RW.
- Sesam keys are namespace-prefixed (`<dataset>:Field`) — stripped before compare; system fields + `Created`/`LastUpdated` + `.test.json` blacklist excluded. `prod` needs `--confirm-prod`.
- **Validator gotchas (2026-06-04, learned the hard way):**
  - **Namespace prefix is the *source* pipe's, not the dataset's.** Fields propagated via Sesam `copy *` keep their originating namespace (`forvalter-brukerrolle:Id`, `d365-prosjekt:prosjekt_id`), NOT `<endpoint-dataset>:`. `strip_prefix` now strips ANY single leading `<ns>:` (leaving `_*`/`rdf:*`). A `0 matched / sesam_only=0` signature = the id_field wasn't found → suspect a prefix/field-name mismatch (a validator artifact), NOT necessarily an RW bug. Diagnose by fetching a RAW Sesam entity (`sesam_get_page`) and printing its keys.
  - **REST sinks (`*-rest` pipes) wrap rows in `{operation, payload:{…}}`.** `sink_sesam_map.json` must point at the flat **pre-envelope `source.dataset`** (e.g. `customer-bq`, not `customer-bq-rest`), else fields are nested under `payload` and no id is found. Check via `grep '["add","payload"' <pipe>`.
  - **Where a fix is reflected:** sink-SELECT changes (Id expr, filter, picking an existing column) appear after `dbt compile` (no re-poll); upstream **mart** changes (e.g. `mrt_global_sale`) need `dbt run <mart> --target <env>` before a sweep sees them (the script reads the live MV by name). `.test.json`/map changes are read at runtime (no compile).
  - **Over-production with correctly-deduped marts = source-population mismatch** (e.g. live webhook vs a Sesam migration snapshot), a domain question — do NOT invent a filter to force the row counts to match.
- **Deploy/poller gotchas (2026-06-04, see [[project_deploy_gotchas]]):**
  - **Poller can't see staging after a deploy = ownership/privilege, NOT a poller bug.** Pollers connect as `risingwave`; dbt/`deploy.sh` as `risingwave-<env>`. A deploy recreates the `table_with_connector` staging tables owned by `risingwave-<env>`; RisingWave `information_schema` is privilege-filtered, so the poller's `risingwave` user can't see them → "Table not found / No columns from source match the schema — skipping publish" → marts go 0-rows. **Fix:** `python scripts/grant_poller_access.py <env>` (grants the poller user; idempotent, prod-gated). **Prod-cutover blocker.**
  - **`--full-refresh` is required to change an existing MV/sink** — a normal `dbt run`/`deploy.sh` NO-OPs them (`[skip … ]`). Scope it to **marts** (`./deploy.sh <env> --select mrt_x+ --full-refresh` — recreates downstream sinks, NOT upstream staging). **NEVER** blanket-`--full-refresh` the project: it empties poller `table_with_connector` staging until the next poll. Sequence: deploy → *wait for full completion* → re-poll → sweep; never overlap (overlap → false RW_EMPTY / "schema mismatch").
  - **STALE COMPILE:** the sweep reads the dbt-**compiled** sink SELECT — after editing a sink or pulling a branch, run `dbt compile --select tag:sink --target <env>` BEFORE sweeping, or you get phantom ID_MISMATCH (bit us on prosjektbudsjett/customer_bq).
  - **Building-only bygg records (`has_avdeling`):** `mrt_global_property` FULL OUTER JOINs avdeling⟗building, key `COALESCE(ba.bygg_avdeling_id, b.bygg_id)`, so `d365-building`-only records (no avdeling, e.g. N20101/N25403) flow to forvalter/bqeos (Sesam keys them by `bygg_id` → parity). kundeportal/miljoprofil EXCLUDE them via `AND has_avdeling` (Sesam keys those by `BuildingId`/`BUILDINGID`, absent from `stg_d365_building`).

## RisingWave Gotchas

See `memory/MEMORY.md` for full notes. Key ones:

**NOW() in streaming materialized views**
Only valid as: `input_col cmp DATE_TRUNC/NOW_EXPR` — e.g.:
```sql
WHERE MAKE_DATE(aar::INT, 1, 1) >= DATE_TRUNC('year', NOW())
```
Never `EXTRACT(YEAR FROM NOW())::INT` — the cast breaks the monotonicity check.

**Column case-folding**
Unquoted identifiers fold to lowercase. Always use lowercase column names when
referencing staging tables whose DDL used unquoted PascalCase identifiers.
Diagnose with: `SELECT column_name FROM information_schema.columns WHERE table_name = '...'`

**SuperOffice webhook payload — camelCase JSON keys**
The SuperOffice webhook sends JSON with camelCase keys (e.g. `ticketId`, `createdAt`, `numMessages`).
JSONB `->>` and `->` operators are case-sensitive, so mart models must use camelCase key strings.
Nested objects also use camelCase (`person`, `category`, `status` and their fields).
Example: `payload->>'ticketId'`, `payload->'person'->>'contactId'`.
PascalCase extractions (`payload->>'TicketId'`) will always return NULL.

**dbt partial parse cache**
After editing models, add `--no-partial-parse` if you see "Invalid column" errors
that don't match the source file.

**dbt Jinja config block**
`{{ config(...) }}` must end with `}}` — a single `}` causes silent compile failure.
SQL comments (`--`) inside `{{ config({...}) }}` also break compilation (causes "expected token ',', got ':'" error). Put all comments outside the config block.

**dbt unit test fixture columns**
Column names in `given` fixture rows must exactly match the staging table DDL. dbt validates fixture columns against the resolved schema. Don't include columns not in the DDL (e.g., omit `_id` if the table uses a different PK name).

**dbt unit test ROUND/NUMERIC comparison**
`ROUND(x::NUMERIC, 2)` for whole-number results may return the value without trailing zeros (e.g., `41324` not `41324.00`). In YAML `expect` rows use integer form (`41324`, `0`) to avoid mismatch; the YAML float `41324.00` parses as `41324.0` which differs from DB `41324`.

**Running unit tests against dev**
`deploy.sh` only runs `dbt run`. To run `dbt test`, load the env file manually:
```bash
cd dbt && python3 -c "
import subprocess, os, sys
env = os.environ.copy()
[env.__setitem__(k.strip(), v.strip()) for line in open('../.env.development') if '=' in line and not line.startswith('#') for k, _, v in [line.rstrip().partition('=')]]
subprocess.run(['dbt', 'test', '--target', 'dev', '--no-partial-parse'] + sys.argv[1:], env=env)
" --select my_model
```

**JDBC MySQL — changing PK on AUTO_INCREMENT table**
Cannot drop a PK column that has AUTO_INCREMENT without keeping a key on that column.
Fix — all in one `ALTER TABLE` statement:
```sql
ALTER TABLE t ADD KEY idx_id (Id), DROP PRIMARY KEY, ADD PRIMARY KEY (Col1, Col2);
```
If you split this into multiple statements, MySQL will error on the intermediate state.

**Env var naming convention**
Use `FORVALTER_MYSQL_DB` / `KUNDEPORTAL_MYSQL_DB` / `MILJOPROFIL_MYSQL_DB` (not `FORVALTER_DB`). Always
include a default: `env_var("FORVALTER_MYSQL_DB", "forvalter-db-dev")`.

**JDBC connection string**
All MySQL JDBC connection strings must include `?nullCatalogMeansCurrent=true` to avoid primary key violation errors (without it, RisingWave queries all catalogs and finds duplicate PK constraints).

**Tombstone / delete propagation pattern**
**RW >= 3.0 note:** webhook tables can instead declare a typed PK column (PK/upsert variant — see `CLAUDE.md` "Materialization Types" and `stg_superoffice_user`); a repeat POST then upserts by PK, so there's **no dedup CTE and no ROW_NUMBER/ordering-field needed** — the append-only+tombstone-dedup pattern below applies only to the remaining single-JSONB (non-PK) webhook tables. Tombstone POSTs on a PK table simply overwrite the live row, so `NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)` filtering in marts still works unchanged.

RisingWave webhook tables **without a declared PK** are append-only — you cannot update or delete rows via the webhook. To propagate deletes to MySQL sinks for those:

1. **C# side** (`SesamDeleteRequest`): has `_deleted: true` and `_deletedAt: DateTime.UtcNow`. Delete methods in `RisingWaveWebhookRepository` POST these tombstone payloads to the webhook endpoint.

2. **dbt mart**: wrap the staging SELECT in a dedup CTE using `ROW_NUMBER() OVER (PARTITION BY entityId ORDER BY COALESCE(updatedDate, _deletedAt) DESC NULLS LAST)`, then filter `WHERE rn = 1 AND NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)`.

3. **Sink**: JDBC sink with `type: 'upsert'` automatically issues `DELETE FROM table WHERE pk = ?` when a row disappears from the source MV.

Affected marts (contact, document, ticket) — **user/person converted to PK upsert, no dedup CTE** (see note above):
```sql
WITH latest AS (
    SELECT payload,
           ROW_NUMBER() OVER (
               PARTITION BY (payload->>'entityId')::BIGINT
               ORDER BY COALESCE(
                   (payload->>'updatedDate')::TIMESTAMPTZ,
                   (payload->>'_deletedAt')::TIMESTAMPTZ
               ) DESC NULLS LAST
           ) AS rn
    FROM {{ ref('stg_...') }}
    WHERE (payload->>'entityId') IS NOT NULL
)
SELECT ... FROM latest
WHERE rn = 1
  AND NOT COALESCE((payload->>'_deleted')::BOOLEAN, FALSE)
```

Ordering field per entity:
- contactsimple: `updatedDate`
- user (person): **N/A — PK upsert (see note above), no ordering field needed**
- document: `updatedDate`
- ticket: `lastChanged`

**Poller reconciliation pattern**
Entity pollers only upsert — they never delete. If an entity is removed from the source system, its row persists in the RisingWave staging table indefinitely.

Two options for removing stale rows:

**Option A — Reconciliation (automatic, opt-in per entity)**
Set `"EnableReconciliation": true` on the entity in `appsettings.json`. After each successful poll, `RisingWaveSqlService.ReconcileAsync` runs a single server-side DELETE:
```sql
DELETE FROM "schema"."table"
WHERE CAST("pkColumn" AS TEXT) <> ALL(SELECT unnest($1::text[]))
```
The current PK set (already in memory from the poll) is sent as an array parameter — no extra SELECT round-trip to RisingWave. Built-in guards:
- **0 rows returned**: skip (safety — refuse to delete everything if API failed)
- **> 100 000 rows**: skip with warning (parameter too large; use full-refresh instead)
- **composite PK**: skip with warning (only single-column PKs supported)

**Do NOT enable when** `WhereClause` is set on a BigQuery table — only a filtered subset is returned, reconciliation would delete all rows outside that filter.

**Option B — Full-refresh re-poll (manual, for large tables)**
```bash
# 1. Drop and recreate the staging table
./deploy.sh prod --select stg_d365_areas --full-refresh

# 2. Restart the poller Cloud Run job so it re-inserts all current rows
# Any entity missing from the source simply won't be re-inserted.
# The JDBC sink will issue MySQL DELETE for disappearing rows automatically.
```

**When to use which:**
| Scenario | Option |
|---|---|
| Entity table, < 100k rows, full fetch | A — reconciliation |
| Entity table with WhereClause filter | B — full-refresh |
| Time-series / append-only BQ table | Neither — rows should never be deleted |
| Large BQ table (> 100k rows) | B — full-refresh |

## Model Layer Summary

| Layer | Count | Materialization | Path |
|-------|-------|----------------|------|
| Sources | 3 | `source` | `models/sources/` |
| Staging | 56 | `table_with_connector` | `models/staging/` |
| Marts | 38 | `materialized_view` | `models/marts/` |
| Sinks | 43 | sink | `models/sinks/` |

## Known Open Issues

| Issue | Detail |
|-------|--------|
| `okonomiskforhold_sistvurdert` still NULL | Not present in BQ `dim_leverandor` export — remains `NULL::TIMESTAMPTZ` in `mrt_global_leverandorvurdering` |
| superoffice-pubsub-writer | Cloud Run job to pull PubSub topics and POST to SO API not yet implemented — plan in `.claude/plans/mutable-doodling-lobster.md` |
| Leko sinks | Connector type TBD — currently stubbed |

## Supporting Reference

See [reference.md](reference.md) for:
- Full Sesam global → RisingWave mapping table
- Sesam endpoint → sink mapping table
- CDC source configuration details
- MySQL CDC prerequisites
- dbt unit test patterns and gotchas
