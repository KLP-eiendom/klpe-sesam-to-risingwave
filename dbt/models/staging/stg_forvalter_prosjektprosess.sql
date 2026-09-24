{{ config(materialized='table_with_connector') }}

CREATE TABLE {{ this }} (
    _id                             VARCHAR PRIMARY KEY,
    ProsjektId                      VARCHAR,
    ProsessInstansId                VARCHAR,
    Byggnummer                      VARCHAR,
    D365ProsjektId                  VARCHAR,
    Forvaltningsdirektor            VARCHAR,
    OpprettetAv                     VARCHAR,
    Prosjekteier                    VARCHAR,
    Prosjektleder                   VARCHAR,
    Prosjektkontroller              VARCHAR,
    Teknisksjef                     VARCHAR,
    Utviklingsdirektor              VARCHAR,
    RegistreringStatus              INTEGER,
    Steg                            VARCHAR,
    Type                            VARCHAR,
    SuperOfficeDocumentId           VARCHAR,
    ProsjektlederHarAvholdtMote     BOOLEAN,
    Created                         TIMESTAMP,
    LastUpdated                     TIMESTAMP
);
