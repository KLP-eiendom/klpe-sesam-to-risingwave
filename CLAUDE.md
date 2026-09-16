# CLAUDE.md — KdiRisingWave

Guidance for AI assistants in this codebase.

## Project Overview

RisingWave streaming-database integration hub for KLP Eiendom. Ingests data from multiple source systems into a PostgreSQL-compatible streaming DB for real-time analytics — replacing Sesam.io as the integration hub. All RisingWave DDL is managed by dbt (`dbt-risingwave` adapter).

## Repository Structure

```
dbt/                  # dbt project — ALL RisingWave DDL & views
  models/{sources,staging,marts,sinks}/   # see Model Layers
  seeds/  scripts/  profiles.yml  deploy.sh
kubernetes/           # K8s manifests (dev/test/prod)
sql/                  # legacy raw SQL (deploy orchestration only)
src/cloud-run/
  RisingWavePollerCommon/    # shared lib (OAuth, RisingWaveSqlService, IdExpression)
  superoffice-entity-poller/ # KDI REST → RW
  bigquery-entity-poller/    # BigQuery → RW (D365 + Energinet)
  eiendom-entity-poller/     # eiendom-api REST → RW (children flattening)
  fdvweb-entity-poller/      # fdvweb REST → RW
  mysql-entity-poller/       # MySQL → RW (Forvalter + Kundeportal)
  pubsub-writer/             # reads PubSub topics, POSTs to SuperOffice
  risingwave-data-api/       # read API over RisingWave
  sink-error-collector/      # forwards RW sink errors to Cloud Logging
terraform/  tests/
```

Cloud Run jobs/schedules for these services are defined in a separate internal infrastructure repo, not here. CI/CD is Azure DevOps (no pipeline YAML in-repo).

## Git Workflow

**Never commit directly to `main` in this repo.** Always create/use a feature branch (this repo's convention: `klpe-<ticket>`) before committing, even for small fixes. If a commit lands on `main` by mistake, cherry-pick it onto the correct branch and reset local `main` back to `origin/main` — don't leave it there.

## Building

```bash
dotnet build KdiRisingWave.sln                                              # whole solution
dotnet build src/cloud-run/superoffice-entity-poller/SuperOfficeEntityPoller.csproj  # one poller
```

No C# test suite — validate pollers by building (0 errors). dbt tests live in `dbt/models/*/unit_tests/`.

**StyleCop SA1204** (enforced by `Klpe.Stylecop`): private static methods come BEFORE private instance methods in a class.

## dbt

### Dev tools (one-time)

```bash
pip install dbt-osmosis sqlfluff sqlfluff-templater-dbt
```

- **dbt-osmosis** — generates/updates `schema.yml` column docs from SQL models
- **sqlfluff** — SQL linter/formatter with Jinja2/dbt support; config in `dbt/.sqlfluff`

`deploy.sh` finds `dbt` on PATH, else probes the usual Python install layouts (including a Microsoft Store Python, whose console scripts live under `AppData/Local/Packages/.../LocalCache/local-packages/PythonXY/Scripts`, nowhere near its interpreter). If it still can't find it: `DBT_BIN=/path/to/dbt.exe ./deploy.sh …` — `PYTHON_BIN` works the same way.

### Running

```bash
cd dbt
dbt run                              # all models → dev (default target)
dbt run --select stg_superoffice_ticket | staging.* | marts.*
dbt run --target {test|prod|ci}
dbt clean
```

**Profiles** (`dbt/profiles.yml`): `dev` is default; `test`/`prod`/`ci` need `DBT_RW_HOST`, `DBT_RW_USER`, `DBT_RW_PASSWORD`.

### Deploying — `dbt/deploy.sh`

RisingWave dev runs in GKE (no external IP); `deploy.sh` handles port-forwarding + env/Vault loading. (test/prod are RisingWave Cloud — direct SSL, no port-forward.)

```bash
cd dbt
./deploy.sh                  # all models → dev (default)
./deploy.sh {dev|test|prod}
./deploy.sh test --select stg_superoffice_ticket    # any dbt flags pass through
./deploy.sh prod --exclude tag:sink
```

**Deploy gotchas (prod-cutover prerequisites):**
- **Pollers need a GRANT after a staging recreate.** Pollers connect as RW user `risingwave`; dbt deploys as `risingwave-<env>` (the table owner). RisingWave's `information_schema` is privilege-filtered, so when a deploy (re)creates `table_with_connector` staging tables, the poller's user can't see them → logs `No columns from source match the schema — skipping publish`, writes nothing (marts drop to 0 rows). Fix: `python scripts/grant_poller_access.py <env>` (idempotent; prod gated by `--confirm-prod`), then re-poll. Durable fix TBD (unify the user, or a dbt on-run-end GRANT).
- **`--full-refresh` is required to change an existing MV/sink.** A plain `dbt run`/`deploy.sh` NO-OPs existing `materialized_view`/`sink` models (`[skip …]`). Scope it to model + downstream: `./deploy.sh test --select mrt_global_property+ --full-refresh`. **Never blanket-`--full-refresh` the whole project** — it drops+recreates poller staging tables, emptying them until the next poll.
- **A new seed needs `./deploy.sh <env> --seed`.** `deploy.sh` runs `dbt seed` only when that flag is passed (it then seeds everything, before `dbt run`) — unlike `run-test.sh`/`fast-test.sh`, which always seed. Deploy a model that joins a brand-new seed without it and the model fails with `Catalog error … table or source not found: <seed_name>`, which reads like a missing model rather than a missing seed.
- **Sequence:** deploy → wait for full completion → re-poll → validate. Never overlap a deploy with a running poll (races the table recreate → transient schema-mismatch / false `RW_EMPTY`).

**Env → file/cluster mapping:**

| Env | .env file | GKE cluster | GCP project |
|-----|-----------|-------------|-------------|
| `dev` | `.env.development` | `cluster-dev` | `example-project-dev` |
| `test` | `.env.test` | `cluster-test` | `example-project-test` |
| `prod` | `.env.production` | `cluster-prod` | `example-project-prod` |

### Local setup & secrets

`cp default.env .env.development`, then set `VaultOptions__TokenId` to a valid short-lived token. All secrets (passwords, API keys, service accounts) live in HashiCorp Vault at `kv/Risingwave/{env}`, fetched by `deploy.sh` via `scripts/fetch_vault_secrets.py`. Only VaultOptions config + operational flags (`*_SINK_MODE`) live in `.env.*`. The `localdev` env skips Vault — put all vars in `.env.localdev`.

Token renewal (8h expiry): `vault token renew -address=https://vault.example.com` (or `vault login`). All clusters in `europe-north1`; `deploy.sh` fetches kubectl creds if missing. Cluster user `root`, no password.

Each `.env.*` also needs `RW_WEBHOOK_SECRET` (embedded in `VALIDATE AS secure_compare` for all webhook tables).

### Sink Mode Control

During migration, destinations can be held `paused` so Sesam stays authoritative while RW sinks exist but don't write. Set `<SYSTEM>_SINK_MODE=paused` in `.env.*`, then `./deploy.sh <env>` — the script applies `ALTER SINK … PAUSE/RESUME` to matching sinks after every run (even when smart-deploy finds no model changes). Default (absent) = `running`.

**`paused` also excludes the group from the dbt run** (`deploy.sh` adds `--exclude *snk*<group>`). For a sink that already exists that just means "don't change it, keep it paused" — but a **brand-new** sink in a paused group is never created at all. Creating it is a deliberate later step: flip the mode to `running` and deploy that sink by name.

| Env var | Destination | Sink name pattern |
|---|---|---|
| `FORVALTER_SINK_MODE` | Forvalter MySQL | ends `_forvalter` |
| `KUNDEPORTAL_SINK_MODE` | Kundeportal MySQL | ends `_kundeportal` |
| `SUPEROFFICE_SINK_MODE` | SuperOffice (PubSub) | ends `_superoffice` |
| `BQ_SINK_MODE` | BigQuery | ends `_bq`/`_bqeos` |
| `LEKO_SINK_MODE` | Leko REST | ends `_leko`/contains `_leko_` |
| `POWERAPP_SINK_MODE` | PowerApp SQL | ends `_powerapp` |
| `FINDABLE_SINK_MODE` | KlpeFindable | ends `_findable` |
| `MILJOPROFIL_SINK_MODE` | Miljoprofil MySQL | ends `_miljoprofil` |
| `DALUX_SINK_MODE` | Dalux FM REST (via PubSub) | ends `_dalux` |

To cut a system over: set its mode to `running`, `./deploy.sh prod`, then set `<SYSTEM>_COMPLETION_SINK_PUMP_MODE=manual` in Sesam.

### Sesam Seeding (seed_from_sesam.py)

To manually populate staging tables from Sesam source datasets, use `dbt/scripts/seed_from_sesam.py`. This is critical for empty webhook-fed tables (like `stg_superoffice_user`) to avoid downstream sinks executing false deletes that violate foreign key constraints in target databases.

```bash
cd dbt
# Dry run:
python scripts/seed_from_sesam.py --sesam-env test --rw-env dev --select stg_superoffice_user --dry-run
# Actual seed:
python scripts/seed_from_sesam.py --sesam-env test --rw-env dev --select stg_superoffice_user
# Seed all priority (empty) tables:
python scripts/seed_from_sesam.py --sesam-env test --rw-env dev --all
```

For more details, overrides, and troubleshooting steps, see the [Sesam Seeding Guide](docs/sesam_seeding.md).

### Model Layers


| Layer | Path | Materialization | Purpose |
|-------|------|----------------|---------|
| sources | `models/sources/` | `source` | CDC connector declarations (`src_<system>_cdc.sql`) — only `src_camunda_cdc` remains |
| staging | `models/staging/` | `table_with_connector` | raw ingestion — poller tables, CDC tables, webhooks |
| marts | `models/marts/` | `materialized_view` | typed views over staging (JSONB parsing, joins, enrichment) |
| sinks | `models/sinks/` | `sink` | connector DDL — SELECT from staging/mart, joins allowed |

### Materialization Types

**`source`** — CDC connector (one per database):
```sql
{{ config(materialized='source') }}
CREATE SOURCE {{ this }} WITH (connector='postgres-cdc', ...);
```

**`table_with_connector`** — three variants:

*Poller table* (no FROM — Cloud Run poller inserts rows):
```sql
{{ config(materialized='table_with_connector') }}
CREATE TABLE {{ this }} (_id VARCHAR PRIMARY KEY, field1 VARCHAR);
```
*CDC table* (references a source; only Camunda uses CDC now):
```sql
{{ config(materialized='table_with_connector') }}
CREATE TABLE {{ this }} (Id VARCHAR PRIMARY KEY, ...)
FROM {{ ref('src_camunda_cdc') }} TABLE 'mydb.MyTable';
```
*Webhook table* (`tags=['webhook']`; authenticated by `RW_WEBHOOK_SECRET`):
```sql
{{ config(materialized='table_with_connector', tags=['webhook']) }}
CREATE TABLE {{ this }} (payload JSONB) WITH (connector = 'webhook')
VALIDATE AS secure_compare(headers->>'signature', '{{ env_var("RW_WEBHOOK_SECRET") }}');
```
**PK/upsert variant** (RW >= 3.0; multi-column webhook tables — v2.7.2 rejects them):
```sql
{{ config(materialized='table_with_connector', tags=['webhook']) }}
CREATE TABLE {{ this }} ("personId" BIGINT, payload JSONB, PRIMARY KEY ("personId"))
WITH (connector = 'webhook')
VALIDATE AS secure_compare(headers->>'signature', '{{ env_var("RW_WEBHOOK_SECRET") }}');
```
Decode maps top-level JSON fields to same-named columns case-sensitively — quote camelCase PK columns. Sender must POST the `{"<pkField>": ..., "payload": {...}}` envelope. Repeat POSTs upsert by PK (latest-wins) — no `ROW_NUMBER` dedup mart, no webhook-dedup-cleanup entry needed. Reference: `stg_superoffice_user`.

**`materialized_view`** — typed SELECT over staging:
```sql
{{ config(materialized='materialized_view') }}
SELECT payload->>'field1' AS field1, ... FROM {{ ref('stg_my_webhook') }}
```

### Sink design guidance

Sinks may JOIN directly to reduce RisingWave actor count. Dedicated intermediate marts (`mrt_<name>_<destination>`) are optional — create one only when the same join logic is shared across sinks (e.g. `mrt_bygg_forvalter`, `mrt_sale_forvalter`), not for separation alone. **Never `NULL` a field as a workaround for a missing join — always include the join.**

### Adding things

- **CDC table:** create `models/sources/src_<system>_cdc.sql` (`materialized='source'`) + add to `sources.yml`, then `models/staging/stg_<system>_<entity>.sql` with `FROM {{ ref('src_<system>_cdc') }} TABLE '...'`. (Only Camunda currently uses CDC; Forvalter/Kundeportal moved to `mysql-entity-poller`.)
- **Webhook:** `models/staging/stg_<name>.sql` (webhook pattern + `tags=['webhook']`) and `models/marts/mrt_<name>.sql` (JSONB extraction). Sender must POST header `signature: <RW_WEBHOOK_SECRET>`. For a natural upsert key, use the PK/upsert variant above instead — see `stg_superoffice_user`.
- **BigQuery table:** add to `bigquery-entity-poller/appsettings.json` → `BigQuerySettings.Tables` (`DatasetId`, `TableId`, `TargetTable`, `IdExpression`), then `models/staging/stg_<name>.sql` (poller pattern).
- **MySQL poller table:** add to `mysql-entity-poller/appsettings.json` → matching DB in `MysqlPollerSettings.Databases` (`TableName`, `TargetTable`, `IdExpression`, `EnableReconciliation`), then `models/staging/stg_<system>_<name>.sql` (poller pattern). Forvalter + Kundeportal share one MySQL instance (`localhost`).

### Webhook Secret Rotation

All 12 webhook tables carry `tags=['webhook']`. To rotate:
1. Update `RW_WEBHOOK_SECRET` in each `.env.*`.
2. Update `WebhookSecret` in Vault for every pusher (KdiWebHookWorker, KdiVerifiedApi, KdiLekoWorker, KdiRisikoVurdering).
3. `./deploy.sh prod --select tag:webhook+ --full-refresh` (recreates webhook staging with the new secret + rebuilds dependent marts in order).

### JDBC Sink Patterns (Sesam vs RisingWave)

- **Target tables, not views:** RW `upsert` needs a PK in target metadata. Sesam wrote to writable views (`vProsjektrapport`); RW writes the underlying table (`Prosjektrapport`) so PK validation passes.
- **Partial updates:** RW `upsert` only touches columns in the `SELECT` — omitted columns are **preserved**, not nulled. So RW can own a subset of fields while PowerApp users manage others in the same table.
- **MSSQL case sensitivity:** double-quote PascalCase columns (`prosjekt_id AS "ProsjektId"`).
- **Internal IDs:** don't send Camunda/RW internal IDs (`_id`, `proc_def_id_`, `tenant_id_`) to PowerApp tables unless part of the business schema.
- **MySQL JDBC URL** must include `?nullCatalogMeansCurrent=true` (else duplicate-PK errors across catalogs).

### dbt Unit Tests

One file per mart model in `models/marts/unit_tests/` (13 files); sink tests grouped by area in `models/sinks/unit_tests/` (17 files). `schema.yml` holds column docs + data_tests. No live RisingWave needed.

**Coverage policy:** required for all non-global marts feeding a sink (Sesam pre-endpoint equivalents). `mrt_global_*` intermediates are excluded. Inputs derive from `source.alternatives.test.entities` in the (internal, not part of this repo) Sesam pipe configs.

**Naming:** file `<model>.yml` (or grouped `<area>_tests.yml` for sinks); test `<model>__<scenario>` (double underscore mirrors dbt's auto-generated `not_null_mrt_foo__column`).

```bash
cd dbt
# all unit tests (the env vars only need to be non-empty — needed to parse CDC/webhook models):
FORVALTER_MYSQL_DB=x KUNDEPORTAL_MYSQL_DB=x MILJOPROFIL_MYSQL_DB=x RW_WEBHOOK_SECRET=x dbt test --target dev
# one model:
FORVALTER_MYSQL_DB=x KUNDEPORTAL_MYSQL_DB=x MILJOPROFIL_MYSQL_DB=x RW_WEBHOOK_SECRET=x dbt test --select mrt_kredittvurdering_superoffice --target dev
```

**`#id` test-row identity:** every expected row (in `expected_data/*.json` and YAML `expect:`) carries `"#id"` — the sink PK value (`col1:col2` for composite). Present in sink SQL only when `target.name in ('localdev','ci')`, via `{{ test_id('<pk_expr>') }}`; never deployed to real RW. `verify_e2e.py` maps `#id`→PK via `id_field` in `*.test.json`, then strips it before comparison.

### Sink Validation (Sesam ↔ RisingWave) — read-only

Both tools are strictly read-only (`SELECT` on RW via the compiled sink SELECT; `GET` on Sesam). They reuse `verify_sink_counts.py`'s Vault/cred bootstrap + `sink_sesam_map.json` (sink → Sesam **source** dataset; regenerate when pipes change — the Sesam `*-endpoint` pipes themselves return 503, so we read their upstream `source.dataset`). Vault: RW creds `kv/risingwave/<env>` (lowercase r), Sesam token + base URL `kv/kdi/<env>`. **`prod` requires `--confirm-prod`; nothing automated targets prod.**

```bash
cd dbt
dbt compile --select tag:sink --target test     # produce compiled SELECTs first (re-run after editing a sink — stale compile = stale results)
python scripts/verify_sink_counts.py test        # Tier 1: counts
python scripts/verify_sink_values.py test         # Tier 2: ID parity + value diffs
python scripts/verify_sink_values.py test --select snk_firma_forvalter
```

**Tier 1 — counts** (`verify_sink_counts.py`): per sink reports **RW mart** (`COUNT(*)` of the MV the sink reads `FROM`, no WHERE), **RW sink** (compiled SELECT, post-filter), **Sesam** (live non-deleted source count). Status compares RW-mart vs Sesam. A `MISMATCH` in test is usually stale/un-backfilled data, not a bug; for row-expanding JOIN sinks the sink count exceeds the mart count.

**`SESAM_POST_FILTER_NOT_NULL` (in `verify_sink_counts.py`):** some Sesam `*-endpoint` chains have an intermediate `*-rest`/pass-through pipe between the mapped source dataset and the actual send, which applies its own `field != null` filter — invisible to us since that intermediate pipe also 503s like the endpoint itself. The mapped source dataset's raw count then overstates what Sesam really emits, producing a false `MISMATCH`. Diagnose by reading the intermediate pipe's `.conf.json` for a `["filter", ["neq", null, "_S.<field>"]]`-shaped rule; if found, add `"snk_<name>": "<field>"` to `SESAM_POST_FILTER_NOT_NULL` with a comment citing the pipe and the count breakdown that confirmed it (fetches entities and counts non-null `<field>` client-side instead of the fast runtime-metadata count). First instance: `snk_leverandor_omsetning_superoffice` / `contactId`, via `leverandor-omsetning-superoffice-rest.conf.json` (fixed a false -1308 MISMATCH → WARN -4).

**Tier 2 — strict ID parity** (`verify_sink_values.py`): the migration requires PK IDs to be **identical** between Sesam and RW. Rows are matched **only** on the sink's `id_field` — the tool **never** normalizes/strips/transforms keys. An ID that doesn't line up is the finding (`ID_MISMATCH`), to be **fixed in the RisingWave sink** so it emits the ID Sesam wrote — never worked around in the script. Matched rows are also field-compared (catches broken COALESCE, a join that didn't fire, column swap, tz shift). Outputs (gitignored, in `dbt/`): `_summary.csv` (one row/sink, sorted by criticality), `_diffs.csv` (per matched-row field mismatch), `_id_mismatches.csv` (opt-in `--id-mismatches`; the fix-RW worklist), `.json`.

| Status (low→high criticality) | Meaning |
|---|---|
| `PARITY` | all IDs matched + all values equal ✓ |
| `DIFFERENCES` | IDs matched, some values differ |
| `ID_MISMATCH` | RW-only / Sesam-only IDs — the actionable fix-RW finding |
| `NO_ID_FIELD` | no `id_field`, or it isn't a real output column |
| `SESAM_MISSING`/`_DOWN`/`_EMPTY` | Sesam 404 / 503 / 0 rows |
| `RW_EMPTY` | RW sink empty in this env (mart not backfilled) |
| `SKIPPED_LARGE` | RW rows > `--max-rows` (run that sink alone) |
| `NO_SESAM_SOURCE` | no Sesam pipe (e.g. KlpeFindable) — RW-only, intentional |
| `ERROR` | unexpected read failure |

- **Consumption sinks — the one composite-key exception:** the 8 `*consumption_{kundeportal,miljoprofil}` sinks were re-keyed (Sesam composite PK → RW synthetic `UniqueId`), so `id_field` is the business composite (e.g. `[ByggNummer,Type,Unit,Mnd]`; customer adds `KundeNummer`; waste is `[ByggNummer,TypeKode,Mnd]`) and `UniqueId` is blacklisted.
- **CANDIDATE caveat:** RW-only/Sesam-only IDs are candidates, not confirmed bugs. We read the Sesam *source* (input — its endpoint output isn't API-readable); the input keeps namespace prefixes (`superoffice-sale:6501`) the output strips (`6501`), so some "mismatches" are input-vs-output artifacts. **Manually verify each flagged ID against the real destination before changing RW.**

## Pub/Sub Sinks & Writer Configuration

### Pub/Sub Message Keying
All RisingWave Pub/Sub sinks (`connector = 'google_pubsub'`) include the `pubsub.message_key` configuration property. This ensures that downstream consumers can process updates in strict order per entity.

### Retry & Dead-Letter Policies
All Pub/Sub integration subscriptions across `dev`, `test`, and `prod` are configured in Terraform with retry and dead-letter policies to prevent message loss on transient failures:
- **Maximum Delivery Attempts**: 10 attempts before forwarding to a dedicated dead-letter topic (e.g. `*-dead-letter`).
- **Exponential Backoff**: Minimum backoff of `10s` and maximum backoff of `600s`.
- In the `dev` environment, the push subscriptions for KLP Findable (`klpe-findable-building-sync-sub` and `klpe-findable-serviceavtale-sync-sub`) are configured with corresponding dead-letter topics and dead-letter subscriptions.

### Pub/Sub Writer Grouping & Counting
The `pubsub-writer` service (`WriterService.cs` inside `src/cloud-run/pubsub-writer/`):
- Groups pulled messages by their primary key value during each polling cycle to process bulk updates efficiently.
- Tracks a running count of processed messages per primary key using an in-memory `ConcurrentDictionary` (`processedCounters`). Since the background service is registered as a singleton, this count persists across polling cycles for the lifetime of the running container process.
- Logs both grouped batch information and running totals per primary key to improve observability and detect high-frequency updates.

## C# Pollers

### RisingWavePollerCommon (shared lib)

| Type | Purpose |
|------|---------|
| `IOAuthApiSettings` | TokenUrl, ClientId, ClientSecret, Scope |
| `OAuthTokenService` | token cache + client_credentials grant |
| `RisingWaveSqlService` | batch upsert via Npgsql; uses `IRisingWaveTableConfig`; opt-in `ReconcileAsync` deletes |
| `IRisingWaveTableConfig` | `ResolvedTargetTable`, `EffectivePrimaryKeyColumns` |
| `IdExpressionEvaluator` | evaluates Sesam DTL subset: concat, coalesce, lower, upper, string, date |
| `PublishResult` | `SuccessCount` + `ErrorCount` |

**IdExpression** examples: `"byggNavnId"`, `"concat(byggNavnId, \"-\", bildearkivTekst)"`, `"concat(BuildingId, \"-\", coalesce(MeteringpointId, \"_null_\"), \"-\", MndString)"`. Use `coalesce(field, "_null_")` for nullable fields in composite keys.

### Adding a REST API poller

Model after `superoffice-entity-poller` (flat) or `eiendom-entity-poller` (nested children). Create under `src/cloud-run/<name>-entity-poller/`: `<Name>EntityPoller.csproj` (+ `RisingWavePollerCommon` ref), `Program.cs`, `StartUp.cs` (registers ApiSettings, `IOAuthTokenService`, API client, `RisingWaveSqlService`), `PollerService.cs` (`BackgroundService` over `apiSettings.Entities`), `Settings/<Name>ApiSettings.cs` (`IOAuthApiSettings`), `Settings/EntityPollConfig.cs` (`IRisingWaveTableConfig`), `Services/I<Name>ApiClient.cs` + impl (applies `IdExpressionEvaluator.Evaluate()`), `Dockerfile`+`.dockerignore` (copy a sibling, fix DLL name), `appsettings.json`. URL construction differs per poller: superoffice `{KdiApiBaseUrl}/kdi/{EntityPath}`; eiendom `{BaseUrl}/{EntityPath}`; fdvweb `{BaseUrl}/{EntityPath.TrimStart('/')}`. Then add to `KdiRisingWave.sln` (new GUID in the Project block, ProjectConfigurationPlatforms, and NestedProjects under `src` folder GUID `{02EA681E-C7D8-13C7-8484-4AC65E1B71E8}`).

**Children flattening (`emit_children`):** model after `eiendom-entity-poller`. `EntityPollConfig` adds `ChildrenPath` (array property on parent), `ParentKeyField`, `ParentKeyTargetField`, and `IdExpression` (evaluated against the child dict after the parent key is copied in).

### Secrets

`appsettings.development.json` / `appsettings.local.json` are gitignored — never commit. Creds injected at runtime from Vault (`VaultOptions`); leave `ClientId`/`ClientSecret`/`SqlPassword` empty in committed `appsettings.json`.

## Sesam → RisingWave Mapping

Sesam "global" pipes merge sources into a canonical master. In RW that's either the staging table (single-source) or a mart (multi-source merge). Sesam pipe configs live in a separate internal repo, not here.

### Multi-source globals (mart models)

| Sesam global / intermediate | RisingWave mart | Sources merged |
|---|---|---|
| `global-leverandor` | `mrt_global_leverandor` | stg_d365_leverandor (drives) + SO contactsimple (joined via custom field 15 = d365-leverandornummer) |
| `global-user` | `mrt_global_user` | stg_superoffice_user webhook |
| `global-internaluser` | `mrt_global_internaluser` | stg_d365_ansatt (drives) + stg_superoffice_user; join `lower(epost)=lower(email)` |
| `global-document` | `mrt_global_document` | stg_superoffice_document + stg_verified_envelope (documents[]) + stg_leko_kontrakt; join via unique_verified_id |
| `global-kredittvurdering` | `mrt_global_kredittvurdering` | SO contactsimple + bisnode-leverandor + bisnode-sanksjoner |
| `global-leverandorvurdering` | `mrt_global_leverandorvurdering` | SO contactsimple + bisnode-leverandor + d365-leverandor + bisnode-sanksjoner |
| `global-project` | `mrt_global_project` | superoffice-project (poller) + superoffice-projectsimple (webhook) |
| `global-sale` | `mrt_global_sale` | superoffice-sale (poller) + superoffice-salesimple (webhook) |
| `global-customer` | `mrt_global_customer` | stg_d365_kunde + SO contact (joined via orgnr; CustomerNumber is legacy) |
| `global-property` | `mrt_global_property` | stg_d365_building + stg_d365_bygg_avdeling + stg_d365_areas + mrt_d365_areal_grouped + mrt_fdvweb_energy_categorization; vacant-area from BQ |
| `global-ticketcategory` | `mrt_global_ticketcategory` | stg_superoffice_ticketcategory (property) + stg_superoffice_supportcategory (support) + stg_kundeportal_ticketcategory |
| `global-invoice` | `mrt_global_invoice` | `SELECT *` + `CommonId=UPPER(firma_id-kunde_nummer-faktura_nummer)` from stg_d365_faktura_detaljer |
| `global-purring` | `mrt_global_purring` | stg_d365_purring_detaljer |
| `global-ticketmessage` | `mrt_superoffice_ticketmessage` (poll) + `_update` (webhook) | consumed by snk_ticketmessage_kundeportal (FULL OUTER JOIN, poll priority) |
| `d365-…-arealer-grouped` | `mrt_d365_areal_grouped` | stg_d365_areas grouped by bygg_avdeling_id |
| `fdvweb-energy-categorization` | `mrt_fdvweb_energy_categorization` | stg_fdvweb_building + fdvweb_helper_energy seed (heating category; energy grade is a gap) |
| `d365-leverandor-omsetning-grouped` | `mrt_leverandor_omsetning_superoffice` | stg_d365_leverandoromsetning + stg_d365_leverandor + mrt_global_leverandorvurdering |
| `d365-kunde-kontrakt-leie-grouped` | *(no mart — inlined in `snk_kunde_leie_superoffice`)* | stg_d365_kunde/kontrakt/contract_line + mrt_superoffice_contactsimple + mrt_global_customer |

Destination-prep marts that aren't `mrt_global_*`: `mrt_bygg_forvalter` (read by all bygg sinks), `mrt_sale_forvalter` (both sale sinks), `mrt_superoffice_project_juridiskselskap`, `mrt_document_bq`, `mrt_*_leko` (bygg/byggtegning/customer/user).

### Single-source globals (staging = canonical)

`global-ticket`→`stg_superoffice_ticket`→`mrt_superoffice_ticket` · `global-envelope`→`stg_verified_envelope`→`mrt_verified_envelope` (+`mrt_verified_document` via documents[], +`mrt_verified_personkonvolutt` via owners[]/recipients[] UNION ALL) · `global-contract`→`stg_d365_kontrakt` · `global-contract-details`→`stg_d365_contract_line` · `global-firma`→`stg_d365_firma` · `global-rentalobject`→`stg_d365_leieobjekt` · `global-prosjekt`→`stg_d365_prosjekt` · `global-budget`→`stg_d365_prosjektbudsjett` · `global-kostkategori`→`stg_d365_kostkategori` · `global-ticketstatus`→`stg_superoffice_ticketstatus` · `global-byggtegning`→`stg_kundeportal_byggtegning` · `global-dokumentkontraktslinjeavsjekk`→`stg_forvalter_dokumentkontraktslinjeavsjekk` · `global-brukerrolle`→`stg_forvalter_brukerrolle` · `global-prosjektprosess`→`stg_forvalter_prosjektprosess` · `global-serviceavtale`→`stg_fdvweb_serviceavtale`

(`global-contract`/`-details` exclude axapta. `global-geography`, `global-property-object` are axapta-only → not feasible.)

### Documented gaps

| Mart | Gap |
|---|---|
| `mrt_global_customer` | SO contact joined via orgnr (CustomerNumber is legacy/unused) |
| `mrt_global_leverandorvurdering` | `okonomiskforhold_sistvurdert` still NULL — not in BQ `dim_leverandor` export (add `okonomiskforhold_sistvurdert TIMESTAMPTZ` to `stg_d365_leverandor` once exported) |
| `mrt_global_user` | `contactNumber` from `stg_superoffice_csuser` (REST poll) |
| `mrt_global_document` | leko signing not confirmed active in prod |
| ticketmessage / attachment | historical rows only arrive as the ticket webhook delivers `TicketMessages[]`/`ticketAttachments[]` |

### Sinks (`models/sinks/snk_<entity>_<destination>.sql`)

Naming mirrors the Sesam `<entity>-<destination>-endpoint` pipe. **A sink's source is its `FROM {{ ref() }}` — read the file/DAG, don't trust a doc list.** Destinations + pause control are in the Sink Mode Control table above. Non-obvious sources (where it isn't the same-named `mrt_global_*`/`stg_*`):

- **bygg:** `snk_bygg_{forvalter,kundeportal,bqeos,miljoprofil}` ← `mrt_bygg_forvalter`; `snk_bygg_findable` & `snk_energiattest_bqeos` ← `mrt_global_property`
- **sale:** `snk_sale_{forvalter,kundeportal}` ← `mrt_sale_forvalter`
- **kunde-leie:** `snk_kunde_leie_superoffice` ← inlined joins (no mart)
- **leverandorvurdering:** `snk_leverandorvurdering_{superoffice,forvalter,bq}` ← `mrt_global_leverandorvurdering`
- **users:** `snk_user_{forvalter,powerapp}` ← `mrt_global_internaluser`; `snk_user_kundeportal` ← `mrt_superoffice_user`; `snk_usercustomer_{bq,kundeportal}` ← `mrt_global_user`; `snk_user_person_forvalter` ← `stg_superoffice_csuser`
- **tickets:** `snk_ticket_kundeportal` ← `mrt_superoffice_ticket`; `snk_ticketstatus_kundeportal` ← `stg_superoffice_ticketstatus`; `snk_ticketcategory_kundeportal` ← `mrt_global_ticketcategory`; `snk_ticketsupportcategory_kundeportal` ← `stg_superoffice_supportcategory`; `snk_ticketmessage_kundeportal` ← `mrt_superoffice_ticketmessage_update`⟗`mrt_superoffice_ticketmessage`; `snk_ticketmessageattachment_kundeportal` ← `stg_superoffice_ticketmessage_update`
- **juridiskselskap:** `snk_prosjekt_juridiskselskap_superoffice` ← `mrt_superoffice_project_juridiskselskap`
- **dalux:** `snk_leverandor_dalux` ← `mrt_leverandor_dalux_writeback` ⋈ `stg_dalux_leverandor` (join supplies Dalux's companyId; update-only)

**SuperOffice REST sinks** write to a PubSub topic; `pubsub-writer` consumes it and POSTs to the SuperOffice API: `snk_kredittvurdering_superoffice`, `snk_leverandorvurdering_superoffice`, `snk_leverandor_omsetning_superoffice`, `snk_kunde_leie_superoffice`, `snk_prosjekt_juridiskselskap_superoffice`.

**Leko REST sinks** (connector TBD — currently stubbed): `snk_kontrakt_leko`, `snk_customer_leko`, `snk_user_leko`, `snk_bygg_leko`, `snk_byggtegning_leko`.

**Non-obvious deployment notes:**
- **`snk_ticketcategory_kundeportal`:** RW JDBC upsert needs `primary_key` to match the MySQL physical PRIMARY KEY (not a UNIQUE KEY). Kundeportal `Sakskategori` PK was moved `Id`→`(SakskategoriId, System, Type)` by EF migration `20260326085707_…_Add_UniqueConstraint` (UNIQUE KEY kept on `Id` for the SakSakskategori FK). Applied all envs 2026-03-26.
- **Miljoprofil consumption sinks:** `snk_energycustomerconsumption_miljoprofil` + `snk_adjustedenergyconsumption_miljoprofil` write synthesized `UniqueId varchar(255)` as PK, but the Miljoprofil schema still has `int Id` PK on `MaalerDataPerMndPerKunde` / `MaalerDataAdjustedPerMndPerBygg`. They fail to deploy until a `MiljoprofilCommonDAL` migration adds `UniqueId varchar(255) NOT NULL PRIMARY KEY` + drops auto-increment `Id` (parallel to `20260426171026_RefactorToUniqueId`, which did this for `MaalerDataPerMndPerBygg`/`AvfallDataPerMnd`). Keep `MILJOPROFIL_SINK_MODE=paused` meanwhile.
- **`snk_bygg_miljoprofil`** writes `NULL` for `Latitude`/`Longitude`/`BimSyncProjectId`/`TomtAreal` — preserved in Miljoprofil (upsert only updates sent columns); backfill is owned by Miljoprofil-internal jobs.

### Energy grade seed

`dbt/seeds/fdvweb_helper_energy.csv` — 234 rows (13 building categories × 3 EnergiSkalaId values × 6 grades A–F): `id, energiskalaid, buildingcategoryname, value` (kWh/m² upper threshold), `grade, arealkorrektsjon`. `mrt_fdvweb_energy_categorization` maps `bygningskategori`→`BuildingCategoryName` (same CASE as Sesam `_buildingEnergyCategory`), finds MIN `value >= energiforbruk` per `(energiskalaid, buildingcategoryname)`, falls back to `'G'`. Load with `dbt seed` — automatic in `run-test.sh`/`fast-test.sh`, but `deploy.sh` only seeds when you pass `--seed`.

## Source Systems (Sesam)

| Sesam system | Auth | Base URL env var | Scope |
|---|---|---|---|
| `fdvweb` | client_credentials | `$ENV(fdvweb-url)` | (none) |
| `fdvweb-api` | client_credentials | `$ENV(eiendom-nord-api-url)` | `fdvwebapi` |
| `eiendom-api` | client_credentials | `$ENV(eiendom-api-url)` | `prosjektapi` |
| `energinet-api` | client_credentials | `$ENV(eiendom-api-url)/kdi/bigquery/` | `bigqueryapi` |
| `superoffice` (KDI gateway) | client_credentials | `$ENV(kdi-api-url)` | `superofficeapi` |

## Table Inventory (poller / CDC / webhook staging)

- **Camunda CDC (2):** camunda-processinstance, camunda-taskinstance
- **SuperOffice poller (8):** contact, project, sale, ticketcategory, ticketstatus, csuser, supportcategory, personinterest
- **BigQuery/D365 poller (21):** d365-ansatt, -building, -bygg-avdeling, -bygg-firma, -kostkategori, -leverandor, -faktura-detaljer, -firma, -garanti, -grunneiendom, -kontrakt, -contract-line, -kunde, -leieobjekt, -prosjekt, -prosjektbilag, -prosjektbudsjett, -purring-detaljer, -areas, -leverandoromsetning, influx-portalusage-sistaktiv
- **BigQuery/Energinet poller (6, EOS_MeterData):** adjustedenergyconsumption, energyconsumption, energycustomerconsumption, maaltall, wasteconsumption, waterconsumption
- **Eiendom API poller (1):** eiendom-prosjektsortedusertask
- **FDV-web poller (3):** fdvweb-building, fdvweb-building-image, fdvweb-serviceavtale (`stg_fdvweb_building_eiendnr` is a derived MV, not a poll)
- **Webhooks (12):** superoffice-contactsimple, -document, -ticket, -salesimple, -projectsimple, -ticketmessage-update, -user, leko-kontrakt, lekoworker-directlink, bisnode-leverandor, bisnode-sanksjoner, verified-envelope
- **MySQL Forvalter poller (3):** forvalter-brukerrolle, -prosjektprosess, -dokumentkontraktslinjeavsjekk
- **MySQL Kundeportal poller (2):** kundeportal-byggtegning, kundeportal-ticketcategory
- **Dalux FM poller (1):** dalux-leverandor (`/2.1/companies`). Auth is a static `X-API-Key` header from Vault, not OAuth. Spec: `docs/dalux-fm-api-2.5.0.json`.

### Dalux vendor write-back (RisingWave → Dalux)

`snk_leverandor_dalux` ← `mrt_leverandor_dalux_writeback` ⋈ `stg_dalux_leverandor` →
PubSub → `pubsub-writer` → `PATCH /2.1/companies/{companyId}`. Update-only: the INNER JOIN
to Dalux's own company list is what supplies `companyId`, and a vendor Dalux doesn't know
simply doesn't emit. Creation is not wired up (the FM API has no idempotency key on POST).

The write-back reads **`mrt_global_leverandorvurdering`** (Bisnode assessment, sanctions,
plus `lokasjon`/`evalueringskommentar`), with a 1:1 lookup into `stg_d365_leverandor` for
the four fields that mart doesn't select from D365 (street, postcode, phone, one-off flag)
and the raw org number. That mart is SuperOffice-driven, so **a D365 vendor with no
SuperOffice contact never reaches Dalux** — deliberate: we maintain the vendors someone has
assessed. `mrt_global_leverandor` is consequently read by nothing, but is kept as the Sesam
parity for `global-leverandor`.

**Dalux is a slave, never a source.** No mart may carry Dalux columns — the cross-reference
belongs in the sink. Ships `DALUX_SINK_MODE=paused`.

`pubsub-writer` does the shaping the sink cannot (`Services/PayloadShaper.cs`), all of it
driven by `SubscriptionConfig`, none of it Dalux-specific in code:
- **null-stripping** — a sink serialises every empty column as `null`, and Dalux reads that
  as "clear this field". Empty means "no opinion", so nulls must never be sent.
- **nested objects** — `address` is assembled from flat `address_*` columns.
- **user-defined fields** — all four are KLP-owned: `Org.nr.`, `Klassifisering`, `Lokasjon`
  and `Vurderingskommentar` (fed by our `evalueringskommentar`, SuperOffice custom field 20 —
  the names differ). Written by echoing Dalux's whole UDF array back with only those values
  replaced, matched on field NAME since the ids are per-environment. Adding a field is two
  lines of `UserDefinedFields.Map` config, not code.

Classification rules live in the seed `dalux_klassifisering_status.csv`, keyed on the
description — SuperOffice's custom-field-16 codes differ per environment while the display
text does not. Any inactivating source wins: D365 block/liquidation/inactive, SO stop, a
classification the seed marks inactive, one-off vendor, or a Bisnode sanctions hit
(`sanksjonert`). Other Bisnode fields are not acted on — Dalux has no field to show them in.
Details: `docs/dalux_leverandor_writeback.md`.