{{ config(materialized='table_with_connector') }}

CREATE TABLE {{ this }} (
    _id             VARCHAR PRIMARY KEY,
    Id              BIGINT,
    SakskategoriId  BIGINT,
    Navn            VARCHAR,
    Parent          BIGINT,
    System          VARCHAR,
    Type            VARCHAR,
    Kode            VARCHAR,
    Created         TIMESTAMP,
    LastUpdated     TIMESTAMP
);
