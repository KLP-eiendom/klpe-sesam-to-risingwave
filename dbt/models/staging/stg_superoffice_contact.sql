{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                            VARCHAR         PRIMARY KEY,
    contactId                      BIGINT,
    category                       VARCHAR,
    business                       VARCHAR,
    country                        VARCHAR,
    number                         VARCHAR,
    code                           VARCHAR,
    orgnr                          VARCHAR,
    stop                           BOOLEAN,
    registeredBy                   VARCHAR,
    registeredDate                 TIMESTAMPTZ,
    nameDepartment                 VARCHAR,
    updatedBy                      VARCHAR,
    updatedDate                    TIMESTAMPTZ,
    primaryKey                     BIGINT,
    entityName                     VARCHAR,
    contactPhoneFormattedNumber    VARCHAR,
    urlURLAddress                  VARCHAR
);
