{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    bankkonto           VARCHAR,
    bygg_navn           VARCHAR,
    bygg_type           VARCHAR,    
    bygg_id             VARCHAR,
    eiendom_id          VARCHAR,
    firma_id            VARCHAR,
    firma_navn          VARCHAR,
    firma_adresse       VARCHAR,
    firma_postnummer    VARCHAR,
    firma_sted          VARCHAR,
    firma_land          VARCHAR,
    girokontonummer     VARCHAR,
    andel               DOUBLE PRECISION,
    gyldig_fra          TIMESTAMPTZ,
    gyldig_til          TIMESTAMPTZ,
    orgnummer           VARCHAR
);
