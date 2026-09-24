{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id       VARCHAR         PRIMARY KEY,
    region    VARCHAR,
    Type      VARCHAR,
    Maaltall  VARCHAR
);
