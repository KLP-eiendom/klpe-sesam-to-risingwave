{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    leieobjekt_id       BIGINT,
    navn                VARCHAR,
    id                  VARCHAR,
    bygg                VARCHAR,
    drift_epost         VARCHAR,
    forvalter_epost     VARCHAR,
    oekonomi_epost      VARCHAR,
    gyldig_fra          TIMESTAMPTZ,
    gyldig_til          TIMESTAMPTZ,
    utleieobjekt_type   VARCHAR,
    drift_d365_id       VARCHAR,
    forvalter_d365_id   VARCHAR,
    oekonomi_d365_id    VARCHAR,
    _is_active          BOOLEAN
);
