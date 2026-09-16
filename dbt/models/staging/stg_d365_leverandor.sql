{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                                     VARCHAR         PRIMARY KEY,
    leverandor_id                           VARCHAR,
    navn                                    VARCHAR,
    organisasjonsnummer                     VARCHAR,
    adresse                                 VARCHAR,
    gate_adresse                            VARCHAR,
    postnummer                              VARCHAR,
    by                                      VARCHAR,
    region_id                               VARCHAR,
    kontakt_epost                           VARCHAR,
    kontakt_tlf                             VARCHAR,
    leverandorgruppe                        VARCHAR,
    leverandorgruppe_navn                   VARCHAR,
    leverandorsperre                        INTEGER,
    merknad                                 VARCHAR,
    underAvvikling                          VARCHAR,
    underTvangsavviklingEllerTvangsopplosning VARCHAR,
    land                                    VARCHAR,
    aktiv                                   VARCHAR,
    engangsleverandor                       VARCHAR
);
