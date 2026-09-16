{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    bygg_id             VARCHAR,
    bygg_navn           VARCHAR,
    adresse             VARCHAR,
    postnummer          VARCHAR,
    sted                VARCHAR,
    kommune             VARCHAR,
    fylke               VARCHAR,
    byggeaar            BIGINT,
    bruksareal          DOUBLE PRECISION,
    fysisk_areal_utleid DOUBLE PRECISION,
    eiendom_id          VARCHAR,
    firma_id            VARCHAR,
    forvalter_epost     VARCHAR,
    oekonomi_epost      VARCHAR,
    drift_epost         VARCHAR,
    anskaffet           VARCHAR,
    bygg_type           VARCHAR,
    land                VARCHAR,
    gyldig_fra          DATE,
    gyldig_til          DATE,
    eid                 VARCHAR,
    forvalter_d365_id   VARCHAR,
    drift_d365_id       VARCHAR,
    oekonomi_d365_id    VARCHAR,
    region              VARCHAR,
    org_level_2         VARCHAR,
    org_level_3         VARCHAR,
    orgenhet_id         BIGINT,
    tilhorer_enhet      VARCHAR
);
