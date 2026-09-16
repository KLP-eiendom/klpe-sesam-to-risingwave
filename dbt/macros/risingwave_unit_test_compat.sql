{#
  Override for risingwave__create_table_as to support dbt 1.8+ unit tests.
  The base dbt unit test framework calls create_table_as with 3 args:
    (temporary, relation, sql)
  but dbt-risingwave only defines the 2-arg version.
  This override adds the optional `temporary` flag.
#}
{% macro risingwave__create_table_as(temporary, relation, sql) -%}
  {%- if temporary -%}
    {# For unit test fixtures, use a simple CREATE TABLE (no "IF NOT EXISTS") #}
    create table {{ relation }} as {{ sql }};
  {%- else -%}
    {{ risingwave__render_sql_header() }}
    create table if not exists {{ relation }}
      {% set contract_config = config.get('contract') %}
      {% if contract_config.enforced %}
        {{ get_assert_columns_equivalent(sql) }}
      {%- endif %}
    as {{ sql }};
  {%- endif -%}
{%- endmacro %}
