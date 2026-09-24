{{ config(materialized='table_with_connector') }}

CREATE TABLE {{ this }} (
    _id             VARCHAR PRIMARY KEY,
    UniqueId        BIGINT,
    Navn            VARCHAR,
    Filnavn         VARCHAR,
    BucketFilnavn   VARCHAR,
    FdvWebByggId    VARCHAR,
    Kategori        VARCHAR,
    Type            VARCHAR,
    Fag             VARCHAR,
    Nummer          VARCHAR,
    Revdato         TIMESTAMP,
    SistVerifisert  TIMESTAMP,
    Created         TIMESTAMP,
    LastUpdated     TIMESTAMP
);
