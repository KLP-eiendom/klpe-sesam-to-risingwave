{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id             VARCHAR         PRIMARY KEY,
    id              VARCHAR,
    name            VARCHAR,
    index           BIGINT,
    ownerRole       VARCHAR,
    formFields      VARCHAR,
    proc_def_key_   VARCHAR
);
