{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id             VARCHAR         PRIMARY KEY,
    personid        VARCHAR,
    contactid       VARCHAR,
    contactnumber   VARCHAR,
    email           VARCHAR,
    firstname       VARCHAR,
    lastname        VARCHAR,
    orgnr           VARCHAR,
    phone           VARCHAR,
    registered      VARCHAR,
    updated         VARCHAR
);
