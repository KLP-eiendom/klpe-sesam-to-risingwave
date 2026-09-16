{{ config(materialized='table_with_connector') }}

CREATE TABLE {{ this }} (
    _id             VARCHAR PRIMARY KEY,
    Id              INTEGER,
    BrukerId        VARCHAR,
    Rolle           VARCHAR,
    Region          VARCHAR,
    Created         TIMESTAMP,
    LastUpdated     TIMESTAMP
);
