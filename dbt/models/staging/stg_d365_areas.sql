{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
    _id                         VARCHAR         PRIMARY KEY,
    grunn_id                    VARCHAR,
    sone_id                     VARCHAR,
    leieobjekt_id               VARCHAR,
    areal_type                  VARCHAR,
    areal_type_navn             VARCHAR,
    etasje                      VARCHAR,
    firma                       VARCHAR,
    kontrakt_id                 VARCHAR,
    fysisk_areal                DOUBLE PRECISION,
    bygg_id                     VARCHAR,
    fra_dato                    TIMESTAMPTZ,
    til_dato                    TIMESTAMPTZ,
    ledig_areal                 DOUBLE PRECISION,
    markedspris_ledig_areal     DOUBLE PRECISION,
    markedspris_pr_m2           DOUBLE PRECISION,
    sone_beskrivelse            VARCHAR,
    sone_nummer                 VARCHAR
);
