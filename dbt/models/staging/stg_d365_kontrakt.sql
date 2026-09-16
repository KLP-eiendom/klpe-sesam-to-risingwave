{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id                 VARCHAR         PRIMARY KEY,
    kundenummer         VARCHAR,
    utleier_id          VARCHAR,
    kontrakt_dato       TIMESTAMPTZ,
    kontrakt_id         VARCHAR,
    kontraktstatus      VARCHAR,
    byggnummer          VARCHAR,
    byggtype            INTEGER,
    kontrakt_navn       VARCHAR,
    fra_dato            TIMESTAMPTZ,
    opphoersdato        TIMESTAMPTZ,
    borett_fra_dato     TIMESTAMPTZ,
    borett_til_dato     TIMESTAMPTZ,
    gyldig_fra          TIMESTAMPTZ,
    gyldig_til          TIMESTAMPTZ,
    lopende             VARCHAR,
    leie                NUMERIC,
    felleskost          NUMERIC,
    eiendomsskatt       NUMERIC,
    lokal_valuta        VARCHAR,
    status_kode         INTEGER,
    status_navn         VARCHAR
);
