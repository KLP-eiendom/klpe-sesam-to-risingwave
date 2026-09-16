{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id               VARCHAR         PRIMARY KEY,
    "bildearkivLink"  VARCHAR,
    "bildearkivTekst" VARCHAR,
    "byggNavnId"      VARCHAR
);
