{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id                    VARCHAR         PRIMARY KEY,
    ticketStatusId         BIGINT,
    name                   VARCHAR,
    status                 VARCHAR
);
