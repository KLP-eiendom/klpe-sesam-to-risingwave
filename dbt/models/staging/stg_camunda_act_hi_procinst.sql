{% if target.name in ('localdev', 'ci') %}
    {{ config(materialized='table_with_connector') }}

    CREATE TABLE {{ this }} (
        _id VARCHAR PRIMARY KEY,
        id_ VARCHAR,

        proc_inst_id_ VARCHAR,
        business_key_ VARCHAR,
        proc_def_key_ VARCHAR,
        proc_def_id_ VARCHAR,
        start_time_ TIMESTAMP,
        end_time_ TIMESTAMP,
        removal_time_ TIMESTAMP,

        duration_ BIGINT,
        start_user_id_ VARCHAR,
        start_act_id_ VARCHAR,
        end_act_id_ VARCHAR,
        super_process_instance_id_ VARCHAR,
        root_proc_inst_id_ VARCHAR,
        super_case_instance_id_ VARCHAR,
        case_inst_id_ VARCHAR,
        delete_reason_ VARCHAR,
        tenant_id_ VARCHAR,
        state_ VARCHAR
    );



{% else %}
    {{ config(
        materialized='table_with_connector'
    ) }}

    -- Contains completed and running process instances with duration and status
    CREATE TABLE {{ this }} (
        id_ VARCHAR PRIMARY KEY,
        proc_inst_id_ VARCHAR,
        business_key_ VARCHAR,
        proc_def_key_ VARCHAR,
        proc_def_id_ VARCHAR,
        start_time_ TIMESTAMP,
        end_time_ TIMESTAMP,
        removal_time_ TIMESTAMP,
        duration_ BIGINT,
        start_user_id_ VARCHAR,
        start_act_id_ VARCHAR,
        end_act_id_ VARCHAR,
        super_process_instance_id_ VARCHAR,
        root_proc_inst_id_ VARCHAR,
        super_case_instance_id_ VARCHAR,
        case_inst_id_ VARCHAR,
        delete_reason_ VARCHAR,
        tenant_id_ VARCHAR,
        state_ VARCHAR
    ) FROM {{ ref('src_camunda_cdc') }} TABLE 'public.act_hi_procinst';
{% endif %}
