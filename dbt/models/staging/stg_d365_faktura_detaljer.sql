{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                              VARCHAR         PRIMARY KEY,
    id                              VARCHAR,
    firma_id                        VARCHAR,
    kunde_nummer                    VARCHAR,
    faktura_nummer                  VARCHAR,
    fakturadato                     TIMESTAMPTZ,
    forfallsdato                    TIMESTAMPTZ,
    betalt_dato                     TIMESTAMPTZ,
    Sum                             NUMERIC,
    sum_innbetalt                   NUMERIC,
    sum_utestaaende                 NUMERIC,
    sum_utestaaende_forsinket       NUMERIC,
    sum_utestaaende_forsinket_dager INT,
    kontraktsnummer                 VARCHAR,
    bygg_nummer                     VARCHAR,
    kid                             VARCHAR,
    faktura_sendt_elektronisk       INT,
    opprettet                       TIMESTAMPTZ,
    sist_oppdatert                  TIMESTAMPTZ,
    siste_innbetaling               TIMESTAMPTZ,
    pdf_filnavn                     VARCHAR,
    fil_finnes                      BOOLEAN
);
