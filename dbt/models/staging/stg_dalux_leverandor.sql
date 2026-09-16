{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    companyId           VARCHAR,
    name                VARCHAR,
    description         VARCHAR,
    organisationId      VARCHAR,
    isActive            BOOLEAN,
    address             VARCHAR,
    phoneNo             VARCHAR,
    email               VARCHAR,
    website             VARCHAR,
    disciplines         VARCHAR,
    companyTypes        VARCHAR,
    userDefinedFields   VARCHAR
);
