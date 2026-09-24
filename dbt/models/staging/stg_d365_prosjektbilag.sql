{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id                 VARCHAR         PRIMARY KEY,
    prosjekt_id         VARCHAR,
    kategori_id         VARCHAR,
    bilag               VARCHAR,
    konto_id            VARCHAR,
    transaksjonsdato    TIMESTAMPTZ,
    belop               DOUBLE PRECISION,
    valuta              VARCHAR,
    beskrivelse         VARCHAR,
    leverandor_id       VARCHAR,
    bygg_avdeling_id    VARCHAR,
    firma_id            VARCHAR,
    kategorigruppe_id   VARCHAR,
    bilagsdato          TIMESTAMPTZ,
    prosjektdato        TIMESTAMPTZ,
    belop_firmavaluta   DOUBLE PRECISION,
    belop_fastvaluta    DOUBLE PRECISION,
    aktivert_kostnad    VARCHAR,
    mvakode             VARCHAR,
    mva                 VARCHAR
);
