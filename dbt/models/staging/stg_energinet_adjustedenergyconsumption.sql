{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id          VARCHAR         PRIMARY KEY,
    BuildingId   VARCHAR,
    month        VARCHAR,
    Value        DOUBLE PRECISION,
    Type         VARCHAR,
    unit         VARCHAR
);
