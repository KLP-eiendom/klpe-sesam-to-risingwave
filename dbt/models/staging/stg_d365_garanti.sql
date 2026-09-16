{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id             VARCHAR PRIMARY KEY,
    garanti_id          BIGINT,
    garanti_nummer      VARCHAR,
    kontrakt_id         VARCHAR,
    garantist_id        BIGINT,
    firma_id            VARCHAR,
    garantist_navn      VARCHAR,
    varslingsdato       TIMESTAMPTZ,
    garantitype         INTEGER,
    klassifiseringstype     VARCHAR,
    klassifiseringskategori VARCHAR,
    gyldig_fra          TIMESTAMPTZ,
    gyldig_til          TIMESTAMPTZ,
    merknad             VARCHAR,
    garantibelop        DOUBLE PRECISION,
    pris_gyldigfra      TIMESTAMPTZ,
    pris_gyldigtil      TIMESTAMPTZ,
    bygg_avdeling_id    VARCHAR,
    Referanse           VARCHAR
);
