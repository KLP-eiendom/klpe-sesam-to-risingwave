{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    eiendom_id          VARCHAR,
    navn                VARCHAR,
    adresse             VARCHAR,
    postnummer          VARCHAR,
    by                  VARCHAR,
    kommune             VARCHAR,
    gnr                 VARCHAR,
    bnr                 VARCHAR,
    snr                 VARCHAR,
    areal               DOUBLE PRECISION,
    firma_id            VARCHAR,
    OWNERSHIPCODE       VARCHAR,
    REGISTRATIONSTATUS  VARCHAR,
    TITLECODE           VARCHAR,
    eiendom_type        VARCHAR,
    eiendom_navn        VARCHAR,
    gyldig_fra          DATE,
    gyldig_til          DATE
);
