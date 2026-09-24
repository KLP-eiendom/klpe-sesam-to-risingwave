{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id              VARCHAR         PRIMARY KEY,
    BuildingId       VARCHAR,
    MeteringpointId  VARCHAR,
    Mnd              VARCHAR,
    MndString        VARCHAR,
    Sum              DOUBLE PRECISION,
    Type             VARCHAR,
    unit             VARCHAR
);
