{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id                 VARCHAR         PRIMARY KEY,
    kundenummer         VARCHAR,
    domene              VARCHAR,
    sist_aktivitet_dato TIMESTAMPTZ,
    antall_innlogginger BIGINT,
    platform            VARCHAR
);
