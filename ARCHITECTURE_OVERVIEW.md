# KLP Eiendom — RisingWave Arkitektur

Teknisk presentasjon for RisingWave-ressurser · April 2026

---

## 1. Systemarkitektur — Oversikt

```mermaid
graph LR
    subgraph SOURCES["Kildesystemer"]
        D365["D365 / BigQuery\n21 tabeller\n(BQ poller)"]
        SO_POLL["SuperOffice REST\n6 tabeller\n(SO poller)"]
        SO_WH["SuperOffice Webhooks\n8 tabeller\n(push)"]
        FDVWEB["FDVweb REST\n3 tabeller\n(FDV poller)"]
        EIENDOM["Eiendom API\n1 tabell\n(eiendom poller)"]
        ENERGINET["Energinet / BigQuery\n6 tabeller\n(BQ poller)"]
        BISNODE["Bisnode\n2 tabeller\n(webhook)"]
        LEKO_SRC["Leko\n2 tabeller\n(webhook)"]
        FORV_CDC["Forvalter MySQL\n3 tabeller\n(CDC)"]
        KP_CDC["Kundeportal MySQL\n4 tabeller\n(CDC)"]
        CAMUNDA["Camunda PostgreSQL\n2 tabeller\n(CDC)"]
    end

    subgraph RW["RisingWave (GKE · 8 RWU)"]
        STG["STAGING\n56 tabeller\n(table_with_connector)"]
        MART["MARTS\n38 materialized views"]
        SINK["SINKS\n46 sink connectors"]
    end

    subgraph API["API-lag (Cloud Run)"]
        DATA_API["RisingWaveDataApi\n(.NET 8)"]
    end

    subgraph TARGETS["Målsystemer"]
        FORV["Forvalter\n(MySQL JDBC)\n15 tabeller"]
        KP["Kundeportal\n(MySQL JDBC)\n13 tabeller"]
        BQ_OUT["BigQuery\n(HTTP sink)\n7 tabeller"]
        SO_PS["SuperOffice\n(via PubSub)\n4 entiteter"]
        FINDABLE["Findable\n(HTTP sink)\n2 tabeller"]
        LEKO_TGT["Leko REST\n4 entiteter\n(PULL)"]
    end

    SOURCES -->|"Cloud Run pollers\n+ webhooks\n+ CDC"| STG
    STG --> MART
    MART --> SINK
    MART -->|"Direkte spørring"| DATA_API
    DATA_API --> LEKO_TGT
    SINK --> FORV
    SINK --> KP
    SINK --> BQ_OUT
    SINK --> SO_PS
    SINK --> FINDABLE
```

---

## 2. Data-lag i detalj

```mermaid
graph TD
    subgraph staging["Staging — 56 tabeller (table_with_connector)"]
        S1["D365-entiteter\n21 tabeller\nBigQuery → RisingWave"]
        S2["SuperOffice poller\n6 tabeller\nKDI REST API"]
        S3["SuperOffice webhooks\n8 tabeller\nJSONB payload"]
        S4["FDVweb poller\n3 tabeller"]
        S5["Energinet poller\n6 tabeller\n(EOS_MeterData)"]
        S6["Bisnode + Leko\n4 webhook-tabeller"]
        S7["MySQL CDC\nForvalter 3 + KP 4"]
        S8["Camunda CDC\n2 tabeller (PG)"]
        S9["Eiendom API\n1 tabell"]
        S10["InfluxDB\n1 tabell\n(portalusage)"]
    end

    subgraph marts["Marts — 38 materialized views"]
        M1["Global merger\nmrt_global_leverandor\nmrt_global_document\nmrt_global_ticketmessage\nmrt_global_property\n..."]
        M2["Webhook-parsere\nmrt_superoffice_ticket\nmrt_verified_document\nmrt_verified_personkonvolutt\n..."]
        M3["Aggregater\nmrt_d365_areal_grouped\nmrt_d365_kunde_kontrakt_leie\nmrt_leverandor_omsetning_superoffice\n..."]
    end

    subgraph sinks["Sinks — 46 connectors"]
        SK1["Forvalter JDBC\n15 MySQL-tabeller"]
        SK2["Kundeportal JDBC\n13 MySQL-tabeller"]
        SK3["BigQuery HTTP\n7 BQ-tabeller"]
        SK4["SuperOffice PubSub\n4 topics"]
        SK5["Findable HTTP\n2 endpoints"]
        SK6["Leko REST ⚠\n4 TBD"]
    end

    staging --> marts --> sinks
```

---

## 3. Cloud Run Pollers

```mermaid
graph LR
    subgraph pollers["Cloud Run Jobs (GKE / Cloud Run)"]
        P1["superoffice-entity-poller\nFlat REST → RW\n6 entiteter"]
        P2["bigquery-entity-poller\nBQ → RW\n27 tabeller (D365 + Energinet)"]
        P3["eiendom-entity-poller\nREST + children-flattening\n1 entitet"]
        P4["fdvweb-entity-poller\nREST → RW\n3 entiteter"]
    end

    subgraph common["RisingWavePollerCommon (shared lib)"]
        LIB1["OAuthTokenService\nclient_credentials"]
        LIB2["RisingWaveSqlService\nbatch upsert (Npgsql)"]
        LIB3["IdExpressionEvaluator\nconcat / coalesce / lower / upper"]
        LIB4["ReconcileAsync\ndelete stale rows"]
    end

    P1 & P2 & P3 & P4 --> common
```

---

## 4. Utviklingsmiljøer

```mermaid
graph TB
    subgraph LOCAL["Lokal utvikling"]
        DEV_IDE["Developer\n(VS Code + dbt)"]
        DOCKER["Docker Compose\nRisingWave lokal"]
        UNIT["dbt unit tests\n53 stk — ingen live RW"]
        SMOKE["dbt run (lokal)\nexcl. sinks + CDC sources\n87 passes"]
        PF["kubectl port-forward\n→ dev-cluster RW\n(ekte data)"]
    end

    subgraph CIDEV["CI / Dev — felles RW-instans (8 RWU)"]
        RW_CIDEV["RisingWave\nGKE europe-north1\nexample-project-dev"]
        DB_CI["Database: ci"]
        DB_DEV["Database: dev"]
    end

    subgraph PROD["Produksjon — separat RW-instans (8 RWU)"]
        RW_PROD["RisingWave\nGKE europe-north1\nexample-project-prod"]
        DB_PROD["Database: prod"]
    end

    DEV_IDE -->|"dbt test --target dev"| UNIT
    DEV_IDE -->|"bash run-test.sh"| DOCKER
    DEV_IDE -->|"deploy.sh dev"| PF --> RW_CIDEV
    RW_CIDEV --> DB_CI & DB_DEV

    GITHUB["GitHub Actions CI"] -->|"dbt run --target ci"| DB_CI
    MERGE["Merge til main"] -->|"deploy.sh dev"| DB_DEV
    RELEASE["Release / tag"] -->|"deploy.sh prod"| RW_PROD --> DB_PROD
```

---

## 5. Deployment-flyt

```mermaid
sequenceDiagram
    participant DEV as Developer
    participant GH as GitHub Actions
    participant RW_DEV as RW dev-instans<br/>(example-project-dev)
    participant RW_PROD as RW prod-instans<br/>(example-project-prod)

    DEV->>DEV: Endre dbt-modell
    DEV->>DEV: dbt test (unit, 53 stk)
    DEV->>DEV: bash run-test.sh (Docker)
    DEV->>GH: git push / PR

    GH->>RW_DEV: dbt run --target ci<br/>(database: ci)
    GH-->>DEV: CI grønn ✓

    DEV->>RW_DEV: deploy.sh dev<br/>(database: dev)
    Note over RW_DEV: kubectl port-forward<br/>Henter GKE creds automatisk

    DEV->>DEV: Verifisér i dev
    DEV->>RW_PROD: deploy.sh prod<br/>(database: prod)
    Note over RW_PROD: Separat GKE-cluster<br/>example-project-prod
```

---

## 6. dbt DDL — Materialiserings-typer

```mermaid
graph LR
    subgraph types["dbt materialiserings-typer (4 stk)"]
        T1["source\nCDC-connector\n3 stk"]
        T2["table_with_connector\nPoller/CDC/Webhook-tabeller\n56 stk"]
        T3["materialized_view\nTypede views over staging\n38 stk"]
        T4["sink\nUt til målsystem\n46 stk"]
    end

    T1 -->|"FROM ref(src_...)"| T2
    T2 --> T3 --> T4
```

---

## 7. Nøkkeltall

| Metrikk | Antall |
|---------|--------|
| Staging-tabeller | 56 |
| Marts (materialized views) | 38 |
| Sinks | 46 |
| CDC-sources | 3 (Forvalter MySQL, Kundeportal MySQL, Camunda PG) |
| Cloud Run pollers | 4 |
| dbt unit tests | 53 |
| Sink-level dbt tests | 39 |
| RisingWave-instanser | 2 (dev/CI delt · prod separat) |
| RWU per instans | 8 |
| Kildesystemer | 9 (D365, SO, FDVweb, Energinet, Eiendom, Bisnode, Leko, Forvalter, Kundeportal) |
| Målsystemer | 6 (Forvalter, Kundeportal, BigQuery, SuperOffice, Findable, Leko) |

---

## 8. Lokal utviklingsflyt — steg for steg

```mermaid
graph TD
    A["1. Installer dev-tools\npip install dbt-osmosis sqlfluff\nsqlfluff-templater-dbt"] --> B

    B["2. Enhetstester (ingen live RW)\nFORVALTER_MYSQL_DB=x ... dbt test --target dev\n→ 53 tester, 0 feil"] --> C

    C["3. Lokal Docker-test\nbash run-test.sh\nDocker Compose RW + dbt run\n→ PASS=87 WARN=0 ERROR=0"] --> D

    D{"Trenger ekte data?"}

    D -->|Nei| E["Ferdig — PR til GitHub"]
    D -->|Ja| F["4. kubectl port-forward → dev-cluster\ndeploy.sh dev --select <modell>"]
    F --> G["5. Verifisér i dev-databasen\npsql -h localhost -p 4566 -d dev"]
    G --> E

    E --> H["6. GitHub Actions kjører\ndbt run --target ci\n(database: ci)"]
    H --> I["7. Grønn CI → deploy til dev\n(automatisk eller manuelt)"]
    I --> J["8. Prod-deploy\ndeploy.sh prod"]
```
