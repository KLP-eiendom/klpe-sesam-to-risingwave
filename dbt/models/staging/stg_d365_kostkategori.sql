{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    kategori_id         VARCHAR,
    kategori            VARCHAR,
    kategori_navn       VARCHAR,
    kategorigruppe      VARCHAR,
    kategorigruppe_id   VARCHAR,
    kategorigruppe_navn VARCHAR
);
