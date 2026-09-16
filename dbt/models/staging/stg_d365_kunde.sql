{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR,
    kundenummer         VARCHAR         PRIMARY KEY,
    navn                VARCHAR,
    navn_alias          VARCHAR,
    adresse             VARCHAR,
    gate_adresse        VARCHAR,
    postnummer          VARCHAR,
    by                  VARCHAR,
    region_id           VARCHAR,
    kontakt_tlf         VARCHAR,
    kontakt_epost       VARCHAR,
    kundegruppe         VARCHAR,
    kundegruppe_navn    VARCHAR,
    mva_nummer          VARCHAR,
    opprettet_dato      TIMESTAMPTZ
);
