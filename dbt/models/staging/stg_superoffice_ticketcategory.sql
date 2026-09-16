{{ config(
    materialized='table_with_connector'
) }}

CREATE TABLE {{ this }} (
_id                    VARCHAR         PRIMARY KEY,
    ticketCategoryId       BIGINT,
    replyTemplate          BIGINT,
    parentId               BIGINT,
    notificationEmail      VARCHAR,
    name                   VARCHAR,
    msgClosingStatus       VARCHAR,
    fullname               VARCHAR,
    flags                  VARCHAR,
    externalName           VARCHAR,
    delegateMethod         VARCHAR,
    closingStatus          VARCHAR,
    categoryMaster         BIGINT,
    assignmentLag          BIGINT
);
