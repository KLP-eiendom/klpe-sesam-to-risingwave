{% if target.name in ('localdev', 'ci') %}
    {{ config(materialized='table_with_connector') }}

    CREATE TABLE {{ this }} (
        _id VARCHAR PRIMARY KEY,
        id_ VARCHAR,

        task_def_key_ VARCHAR,
        proc_def_key_ VARCHAR,
        proc_def_id_ VARCHAR,
        root_proc_inst_id_ VARCHAR,
        proc_inst_id_ VARCHAR,
        execution_id_ VARCHAR,
        case_def_key_ VARCHAR,
        case_def_id_ VARCHAR,
        case_inst_id_ VARCHAR,
        case_execution_id_ VARCHAR,
        act_inst_id_ VARCHAR,
        name_ VARCHAR,
        parent_task_id_ VARCHAR,
        description_ VARCHAR,
        owner_ VARCHAR,
        assignee_ VARCHAR,
        start_time_ TIMESTAMP,
        end_time_ TIMESTAMP,
        duration_ BIGINT,
        delete_reason_ VARCHAR,
        priority_ INTEGER,
        due_date_ TIMESTAMP,
        follow_up_date_ TIMESTAMP,
        tenant_id_ VARCHAR,
        removal_time_ TIMESTAMP,
        task_state_ VARCHAR

    );



{% else %}
    {{ config(
        materialized='table_with_connector'
    ) }}

    -- Contains all user tasks (completed and active) with assignment and timing data
    CREATE TABLE {{ this }} (
        id_ VARCHAR PRIMARY KEY,
        task_def_key_ VARCHAR,
        proc_def_key_ VARCHAR,
        proc_def_id_ VARCHAR,
        root_proc_inst_id_ VARCHAR,
        proc_inst_id_ VARCHAR,
        execution_id_ VARCHAR,
        case_def_key_ VARCHAR,
        case_def_id_ VARCHAR,
        case_inst_id_ VARCHAR,
        case_execution_id_ VARCHAR,
        act_inst_id_ VARCHAR,
        name_ VARCHAR,
        parent_task_id_ VARCHAR,
        description_ VARCHAR,
        owner_ VARCHAR,
        assignee_ VARCHAR,
        start_time_ TIMESTAMP,
        end_time_ TIMESTAMP,
        duration_ BIGINT,
        delete_reason_ VARCHAR,
        priority_ INTEGER,
        due_date_ TIMESTAMP,
        follow_up_date_ TIMESTAMP,
        tenant_id_ VARCHAR,
        removal_time_ TIMESTAMP,
        task_state_ VARCHAR

    ) FROM {{ ref('src_camunda_cdc') }} TABLE 'public.act_hi_taskinst';
{% endif %}
