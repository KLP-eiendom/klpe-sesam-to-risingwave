{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id                 VARCHAR         PRIMARY KEY,
    prosjekt_id         VARCHAR,
    konto_id            VARCHAR,
    bygg_avdeling_id    VARCHAR,
    kontnadsted_id      VARCHAR,
    budsjettdato        TIMESTAMPTZ,
    belop               DOUBLE PRECISION,
    valuta              VARCHAR,
    firma_id            VARCHAR,
    KonDim1Key          VARCHAR,
    KonDim2Key          VARCHAR,
    belop_fast_valutakurs DOUBLE PRECISION,
    belop_firmavaluta   DOUBLE PRECISION,
    belop_transaksjonsvaluta DOUBLE PRECISION,
    belop_valutakors_per_dato DOUBLE PRECISION,
    budsjett_valuta     VARCHAR,
    budsjettmodell      VARCHAR,
    fast_valutakurs     DOUBLE PRECISION,
    kommentar           VARCHAR,
    kontrakt_id         VARCHAR,
    kostsenter_id       VARCHAR,
    kunde_id            VARCHAR,
    leieobjekt_id       VARCHAR,
    leverandor_id       VARCHAR,
    motpart_id          VARCHAR,
    opprinnelse         VARCHAR,
    valuta_id           VARCHAR
);
