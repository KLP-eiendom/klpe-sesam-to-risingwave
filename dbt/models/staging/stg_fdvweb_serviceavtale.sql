{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id               VARCHAR         PRIMARY KEY,
    byggId            VARCHAR,
    id                BIGINT,
    nummer            VARCHAR,
    navn              VARCHAR,
    firma             VARCHAR,
    pris              VARCHAR,
    prisFrekvens      VARCHAR,
    oppsigelsesfrist  VARCHAR,
    varighet          VARCHAR,
    startdato         TIMESTAMPTZ,
    utlopsdato        TIMESTAMPTZ,
    fornyelse         VARCHAR,
    prisregulering    VARCHAR,
    omfang            VARCHAR,
    annet             VARCHAR,
    type              VARCHAR,
    bygningsdel       VARCHAR,
    ansvarlig         VARCHAR,
    oppfolgingsdato   TIMESTAMPTZ,
    garantidato       TIMESTAMPTZ
);
