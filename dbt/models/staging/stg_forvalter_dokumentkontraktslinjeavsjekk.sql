{{ config(materialized='table_with_connector') }}

CREATE TABLE {{ this }} (
    _id                         VARCHAR PRIMARY KEY,
    DokumentId                  VARCHAR,
    KontraktLinjeId             VARCHAR,
    DokumentAvsjekkDokumentId   VARCHAR,
    Created                     TIMESTAMP,
    LastUpdated                 TIMESTAMP
);
