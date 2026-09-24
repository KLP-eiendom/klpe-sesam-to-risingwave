{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                     VARCHAR          PRIMARY KEY,
    leverandor_id           VARCHAR,
    omsetning_belop_i_aar   DOUBLE PRECISION,
    omsetning_belop_i_fjor  DOUBLE PRECISION
);
