{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    bygg_avdeling_id    VARCHAR,
    bygg                VARCHAR,
    byggtype            VARCHAR,
    drift               VARCHAR,
    drift_d365_id       VARCHAR,
    drift_epost         VARCHAR,
    firma_id            VARCHAR,
    forvaltning         VARCHAR,
    forvalter_d365_id   VARCHAR,
    forvalter_epost     VARCHAR,
    okonomi             VARCHAR,
    oekonomi_d365_id    VARCHAR,
    oekonomi_epost      VARCHAR,
    eiendomtype         VARCHAR,
    unique_eiendom_id   VARCHAR
);
