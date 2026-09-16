# KdiRisingWave — Detailed Reference

## Sesam Global → RisingWave Mapping

### Multi-source globals (mart models)

| Sesam global | RisingWave mart | Sources merged |
|---|---|---|
| `global-kredittvurdering` | `mrt_global_kredittvurdering` | SO contactsimple + bisnode-leverandor + bisnode-sanksjoner |
| `global-leverandorvurdering` | `mrt_global_leverandorvurdering` | SO contactsimple + bisnode-leverandor + d365-leverandor + bisnode-sanksjoner |
| `global-project` | `mrt_global_project` | superoffice-project (poller) + superoffice-projectsimple (webhook) |
| `global-sale` | `mrt_global_sale` | superoffice-sale (poller) + superoffice-salesimple (webhook) |
| `global-customer` | `mrt_global_customer` | stg_d365_kunde + SO contact (joined via orgnr — CustomerNumber is legacy, orgnr match is the intended approach) |
| `global-property` | `mrt_global_property` | stg_d365_building + stg_d365_bygg_avdeling + stg_d365_areas + fdvweb energy seed |
| `global-ticketcategory` | `mrt_global_ticketcategory` | stg_superoffice_ticketcategory + stg_superoffice_supportcategory + stg_kundeportal_ticketcategory |
| `d365-utleide/ledige/total-arealer-grouped` | `mrt_d365_areal_grouped` | stg_d365_areas grouped by bygg_avdeling_id |
| `d365-kunde-kontrakt-leie-grouped` | `mrt_d365_kunde_kontrakt_leie` | stg_d365_kunde + stg_d365_kontrakt + SO updatedDate |
| `fdvweb-energy-categorization` | `mrt_fdvweb_energy_categorization` | stg_fdvweb_building + fdvweb_helper_energy seed |
| `d365-leverandor-omsetning-grouped` | `mrt_leverandor_omsetning_superoffice` | stg_d365_leverandoromsetning + stg_d365_leverandor + mrt_global_leverandorvurdering |

### Single-source globals (staging = canonical)

| Sesam global | RisingWave table |
|---|---|
| `global-ticket` | `stg_superoffice_ticket` → `mrt_superoffice_ticket` (mart parses JSONB) |
| `global-envelope` | `stg_verified_envelope` → `mrt_verified_envelope` |
| `global-contract` | `stg_d365_kontrakt` |
| `global-contract-details` | `stg_d365_contract_line` |
| `global-firma` | `stg_d365_firma` |
| `global-rentalobject` | `stg_d365_leieobjekt` |
| `global-prosjekt` | `stg_d365_prosjekt` |
| `global-budget` | `stg_d365_prosjektbudsjett` |
| `global-purring` | `stg_d365_purring_detaljer` |
| `global-kostkategori` | `stg_d365_kostkategori` |
| `global-ticketstatus` | `stg_superoffice_ticketstatus` |
| `global-byggtegning` | `stg_kundeportal_byggtegning` |
| `global-dokumentkontraktslinjeavsjekk` | `stg_forvalter_dokumentkontraktslinjeavsjekk` |
| `global-brukerrolle` | `stg_forvalter_brukerrolle` |
| `global-prosjektprosess` | `stg_forvalter_prosjektprosess` |
| `global-serviceavtale` | `stg_fdvweb_serviceavtale` |

### Not feasible (missing sources)

| Sesam global | Reason |
|---|---|
| `global-geography`, `global-property-object` | Axapta only (excluded) |
| `global-document` | Missing: verified-document, leko-dokument |
| `global-user`, `global-internaluser` | Missing: superoffice-migrateduser |
| `global-ticketmessage` | Missing: full superoffice-ticketmessage |
| `global-ticketmessageattachment` | Missing: both sources |

---

## Sesam Endpoint → RisingWave Sink Mapping

### SuperOffice REST (via PubSub)

| Sesam endpoint | Mart | Sink |
|---|---|---|
| `kredittvurdering-superoffice-rest-endpoint` | `mrt_kredittvurdering_superoffice` | `snk_kredittvurdering_superoffice` |
| `leverandorvurdering-superoffice-rest-endpoint` | `mrt_leverandorvurdering_superoffice` | `snk_leverandorvurdering_superoffice` |
| `leverandor-omsetning-superoffice-rest-endpoint` | `mrt_leverandor_omsetning_superoffice` | `snk_leverandor_omsetning_superoffice` |
| `kunde-leie-superoffice-rest-endpoint` | `mrt_d365_kunde_kontrakt_leie` | `snk_kunde_leie_superoffice` |

### Forvalter MySQL sinks

| Sesam endpoint | Mart | Sink |
|---|---|---|
| `bygg-forvalter-endpoint` | `mrt_global_property` | `snk_bygg_forvalter` |
| `customer-forvalter-endpoint` | `mrt_global_customer` | `snk_customer_forvalter` |
| `firma-forvalter-endpoint` | `mrt_global_firma` | `snk_firma_forvalter` |
| `leieobjekt-forvalter-endpoint` | `mrt_global_rentalobject` | `snk_leieobjekt_forvalter` |
| `prosjekt-forvalter-endpoint` | `mrt_global_prosjekt` | `snk_prosjekt_forvalter` |
| `sale-forvalter-endpoint` | `mrt_global_sale` | `snk_sale_forvalter` |
| `leverandorvurdering-forvalter-endpoint` | `mrt_global_leverandorvurdering` | `snk_leverandorvurdering_forvalter` |
| `prosjektbudsjett-forvalter-endpoint` | `mrt_global_budget` | `snk_prosjektbudsjett_forvalter` |
| `faktura-forvalter-endpoint` | `mrt_global_invoice` | `snk_faktura_forvalter` |
| `user-forvalter-endpoint` | `mrt_global_internaluser` | `snk_user_forvalter` |
| `direktlink-forvalter-endpoint` | `mrt_lekoworker_directlink` | `snk_directlink_forvalter` |
| `kostkategori-forvalter-endpoint` | `mrt_global_kostkategori` | `snk_kostkategori_forvalter` |
| `contract-details-forvalter-endpoint` | `mrt_global_contract_details` | `snk_contract_details_forvalter` |

### Kundeportal MySQL sinks

| Sesam endpoint | Mart | Sink |
|---|---|---|
| `customer-kundeportal-endpoint` | `mrt_global_customer` | `snk_kunder_kundeportal` |
| `bygg-kundeportal-endpoint` | `mrt_global_property` | `snk_bygg_kundeportal` |
| `ticket-kundeportal-endpoint` | `mrt_global_ticket` | `snk_ticket_kundeportal` |
| `ticketstatus-kundeportal-endpoint` | `mrt_global_ticketstatus` | `snk_ticketstatus_kundeportal` |
| `ticketcategory-kundeportal-endpoint` | `mrt_global_ticketcategory` | `snk_ticketcategory_kundeportal` |
| `user-kundeportal-endpoint` | `mrt_superoffice_user` | `snk_user_kundeportal` |
| `sale-kundeportal-endpoint` | `mrt_global_sale` | `snk_sale_kundeportal` |
| `energyconsumption-kundeportal-endpoint` | `stg_energinet_*` | `snk_energyconsumption_kundeportal` |
| `purring-kundeportal-endpoint` | `mrt_global_purring` | `snk_purring_kundeportal` |

### BigQuery sinks

| Sesam endpoint | Mart | Sink | Dataset env var |
|---|---|---|---|
| `customer-bq-rest-endpoint` | `mrt_global_customer` | `snk_customer_bq` | `BQ_SINK_DATASET` |
| `document-bq-rest-endpoint` | `mrt_global_document` | `snk_document_bq` | `BQ_SINK_DATASET` |
| `leverandorvurdering-bigquery-endpoint` | `mrt_global_leverandorvurdering` | `snk_leverandorvurdering_bq` | `BQ_KDI_DATASET` |
| `bygg-bqeos-rest-endpoint` | `mrt_global_property` | `snk_bygg_bqeos` | `BQ_SINK_DATASET` |
| `energiattest-bqeos-rest-endpoint` | `mrt_global_property` | `snk_energiattest_bqeos` | `BQ_SINK_DATASET` |
| `usercustomer-bq-rest-endpoint` | `mrt_superoffice_user` | `snk_usercustomer_bq` | `BQ_SINK_DATASET` |
| `serviceavtale-bq-rest-endpoint` | `stg_fdvweb_serviceavtale` | `snk_serviceavtale_bq` | `BQ_SINK_DATASET` |

---

## CDC Source Configuration

### MySQL CDC (Forvalter + Kundeportal)

Both databases are on the same MySQL instance (`localhost`). Unique `server.id` is required per source so MySQL can track separate replication consumers.

```sql
CREATE SOURCE src_forvalter_cdc WITH (
    connector='mysql-cdc',
    hostname='{{ env_var("FORVALTER_MYSQL_HOST") }}',
    port='{{ env_var("FORVALTER_MYSQL_PORT", "3306") }}',
    username='{{ env_var("FORVALTER_MYSQL_USER") }}',
    password='{{ env_var("FORVALTER_MYSQL_PASSWORD") }}',
    database.name='{{ env_var("FORVALTER_MYSQL_DB", "forvalter-db-dev") }}',
    server.id='5001'
);
```

MySQL prerequisites: `log_bin=ON`, `binlog_format=ROW`, `binlog_row_image=FULL`.
CDC user grants: `SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT`.

### CDC staging table pattern

```sql
CREATE TABLE {{ this }} (
    Id INTEGER PRIMARY KEY,
    Field1 VARCHAR,
    ...
) FROM {{ ref('src_forvalter_cdc') }} TABLE '{{ env_var("FORVALTER_MYSQL_DB", "forvalter-db-dev") }}.TableName';
```

**Note:** RisingWave requires double-quoted identifiers for hyphenated table names.

---

## BigQuery Sink Pattern

The correct connector config — do NOT use `data_format`/`data_encode`/`format_parameters` (they produce an invalid `FORMAT PLAIN ENCODE JSON` clause).

```python
{{ config(
    materialized='sink',
    connector_properties={
        'connector': 'bigquery',
        'type': 'append-only',
        'force_append_only': 'true',
        'bigquery.project': env_var('GCP_PROJECT_ID', 'example-project-dev'),
        'bigquery.dataset': env_var('BQ_SINK_DATASET', 'risingwave_sink'),
        'bigquery.table': 'MyTable',
        'bigquery.credentials.json': env_var('GCP_PUBSUB_CREDENTIALS', '')
    }
) }}
SELECT ... FROM {{ ref('mrt_my_model') }}
```

---

## Known Staging Schema Gaps

### `stg_d365_leverandor` — resolved (fields now in DDL)

The following vendor flag fields were added and are now wired into mart models:

| Field (DDL name) | BQ source field | Used in |
|---|---|---|
| `leverandorsperre BIGINT` | `leverandorsperre` | `mrt_global_leverandorvurdering`, `mrt_leverandor_omsetning_superoffice` |
| `merknad VARCHAR` | `merknad` | `mrt_leverandor_omsetning_superoffice` |
| `underavvikling VARCHAR` | `underAvvikling` | `mrt_leverandor_omsetning_superoffice` |
| `undertvangsavviklingellertvangsopplosning VARCHAR` | `undertvangsavviklingellertvangsopplosning` | `mrt_leverandor_omsetning_superoffice` |
| `engangsleverandor VARCHAR` | `engangsleverandor` | `mrt_leverandor_omsetning_superoffice` |
| `leverandorgruppe VARCHAR` | `leverandorgruppe` | `mrt_leverandor_omsetning_superoffice` |

`okonomiskforhold_sistvurdert` is **still NULL** — not present in BQ `dim_leverandor` export.

Flag computation in marts (values are VARCHAR "ja"/"nei"/null, not BOOLEAN):
- `Sperret`: `(leverandorsperre IS NOT NULL AND leverandorsperre != 0)`
- `UnderAvvikling`: `(underavvikling = 'ja' OR undertvangsavviklingellertvangsopplosning = 'ja')` — NULL inputs give NULL (not false)
- `Engangsleverandor`: `(engangsleverandor = 'ja')` — NULL input gives NULL
- `Konsernintern`: `(leverandorgruppe = '200')` — NULL input gives NULL

### `stg_d365_contract_line` — resolved (fields now in DDL)

All area computation fields were added:

| Field (DDL name) | BQ source field | Purpose |
|---|---|---|
| `areal DOUBLE PRECISION` | `areal` | Rentable area per contract line |
| `areal_ikke_medregnet BIGINT` | `areal_ikke_medregnet` | Flag: 0 = countable |
| `leie_kost_gruppe_id BIGINT` | `leie_kost_gruppe_id` | Cost group (1 = rent, 2 = operating) |
| `antall BIGINT` | `antall` | Count (0 = area-based, >0 = count-based) |
| `gyldig_til TIMESTAMPTZ` | `gyldig_til` | Validity end date |

Sesam `d365-contract-line-area-countable` rule: `medregnet_areal = areal WHERE areal_ikke_medregnet=0 AND leie_kost_gruppe_id=1 AND antall=0`

### `stg_d365_areas` — resolved (fields now in DDL)

| Field (DDL name) | Purpose |
|---|---|
| `ledig_areal DOUBLE PRECISION` | Market-listed vacant area |
| `markedspris_ledig_areal DOUBLE PRECISION` | Market price of vacant area |

---

## dbt Unit Tests

Unit test files live in `dbt/models/marts/unit_tests/<model_name>.yml`.

### Running unit tests

`deploy.sh` only runs `dbt run`. To run tests, load the .env file manually:

```bash
cd dbt && python3 - <<'EOF'
import subprocess, os, sys
env = os.environ.copy()
with open('../.env.development') as f:
    for line in f:
        line = line.rstrip()
        if line and not line.startswith('#') and '=' in line:
            k, _, v = line.partition('=')
            env[k.strip()] = v.strip()
subprocess.run(['dbt', 'test', '--target', 'dev', '--no-partial-parse',
                '--select', 'mrt_my_model'], env=env)
EOF
```

### Fixture column names

Columns in `given` fixture rows must match the staging table's actual DDL columns exactly. dbt resolves the table schema and rejects unknown columns with "Invalid column name: X in unit test fixture".

Common mistake: staging tables use column `leverandor_id` as PK (not `_id`) — remove `_id` from fixtures for those tables.

### Numeric type comparison

`ROUND(x::NUMERIC, 2)` may return whole-number results without trailing zeros (e.g. `41324` not `41324.00`). Use integer form in `expect` rows:

```yaml
expect:
  rows:
    - totalleieareal: 41324   # not 41324.00 or 41324.0
```

### Test naming convention

`<model_name>__<scenario>` (double underscore), e.g. `mrt_d365_kunde_kontrakt_leie__sesam_contract_area`.

### Existing unit tests

| Test name | File | What it covers |
|---|---|---|
| `mrt_kredittvurdering_superoffice__sesam_5_cases` | `mrt_kredittvurdering_superoffice.yml` | 5 Sesam kredittvurdering cases: AA/A ratings, Sanksjonert, RevisorKommentar, Soliditet |
| `mrt_leverandor_omsetning_superoffice__sesam_d365_flags` | `mrt_leverandor_omsetning_superoffice.yml` | D365 vendor flags: Sperret, D365Kommentar, UnderAvvikling, Engangsleverandor, Konsernintern — 2 Sesam entities + 4 synthetics |
| `mrt_d365_kunde_kontrakt_leie__sesam_contract_area` | `mrt_d365_kunde_kontrakt_leie.yml` | totalLeieareal from Sesam contract-line entities 101323/107651 + synthetics |

---

## Energy Grade Seed

`dbt/seeds/fdvweb_helper_energy.csv` — 234 rows (13 building categories × 3 EnergiSkalaId values × 6 grades A–F).

`mrt_fdvweb_energy_categorization` joins this seed: maps `bygningskategori` → standardised `BuildingCategoryName`, finds `MIN(value) >= energiforbruk` for `(energiskalaid, buildingcategoryname)`. Falls back to `'G'` when consumption exceeds all thresholds.

Must be loaded before the mart can be deployed: `dbt seed` (handled automatically by `run-test.sh` and `deploy.sh`).
