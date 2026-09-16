{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                 VARCHAR         PRIMARY KEY,
    id                  VARCHAR,
    firma_id            VARCHAR,
    kunde_nummer        VARCHAR,
    purring_nummer      VARCHAR,
    original_faktura    VARCHAR,
    kid                 VARCHAR,
    purring_kode        VARCHAR,
    purring_kode_navn   VARCHAR,
    faktura_dato        TIMESTAMPTZ,
    valuta              VARCHAR,
    kommentar           VARCHAR,
    status              VARCHAR,
    status_navn         VARCHAR,
    sendt_elektronisk   VARCHAR,
    siste_sendt         TIMESTAMPTZ,
    siste_purring_dato  TIMESTAMPTZ,
    sum_innbetalt       DOUBLE PRECISION,
    fil_forfall         BOOLEAN,
    forfallsdato        TIMESTAMPTZ,
    pdf_filnavn         VARCHAR,
    fil_finnes          BOOLEAN,
    sist_oppdatert      TIMESTAMPTZ,
    siste_innbetaling   TIMESTAMPTZ
);
