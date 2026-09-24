{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                    VARCHAR         PRIMARY KEY,
    projectId              BIGINT,
    name                   VARCHAR,
    text                   VARCHAR,
    number                 VARCHAR,
    description            VARCHAR,
    status                 VARCHAR,
    completed              BOOLEAN,
    type                   VARCHAR,
    associateId            VARCHAR,
    endDate                VARCHAR,
    entityName             VARCHAR,
    hasGuide               BOOLEAN,
    hasInfoText            BOOLEAN,
    icon                   VARCHAR,
    nextMilestone          VARCHAR,
    primaryKey             BIGINT,
    registeredBy           VARCHAR,
    registeredDate         VARCHAR,
    updatedBy              VARCHAR,
    updatedDate            VARCHAR,
    userDefinedFields      VARCHAR,
    ExternalId             VARCHAR
);
