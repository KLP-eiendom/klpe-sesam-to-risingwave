{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                    VARCHAR         PRIMARY KEY,
    persintid              BIGINT,
    personid               BIGINT,
    name                   VARCHAR,
    tooltip                VARCHAR,
    created                VARCHAR,
    updated                VARCHAR
);
