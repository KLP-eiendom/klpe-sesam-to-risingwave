{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    bankkonto           VARCHAR,
    firma_id            VARCHAR,
    navn                VARCHAR,
    gateadresse         VARCHAR,
    girokontonummer     VARCHAR,
    postnummer          VARCHAR,
    poststed            VARCHAR,
    landkode            VARCHAR,
    region              VARCHAR,
    orgnummer           VARCHAR,
    OrgLevel1           VARCHAR,
    OrgLevel2           VARCHAR,
    OrgLevel3           VARCHAR,
    firmavaluta_id      VARCHAR
);
