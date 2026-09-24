{% macro test_id(expression) %}
{% if target.name in ('localdev', 'ci') or var('with_test_id', false) %}
    {{ expression }} AS "#id",
{% endif %}
{% endmacro %}
