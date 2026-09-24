{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id                 VARCHAR         PRIMARY KEY,
    bruker_id           VARCHAR,
    epost               VARCHAR,
    fult_navn           VARCHAR,
    phone               VARCHAR,
    spraak_id           VARCHAR
);
