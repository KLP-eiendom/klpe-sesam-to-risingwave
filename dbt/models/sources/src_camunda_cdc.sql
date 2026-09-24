{% if target.name in ('localdev', 'ci') %}
    {{ config(materialized='view') }}
    SELECT 1 WHERE FALSE

{% else %}
    {{ config(materialized='source') }}

    CREATE SOURCE {{ this }} WITH (
        connector='postgres-cdc',
        hostname='{{ env_var("CAMUNDA_HOST", "localhost") }}',
        port='5432',
        username='{{ env_var("CAMUNDA_USER", "risingwave-cdc-user") }}',
        password='{{ env_var("CAMUNDA_PASSWORD", "") }}',
        database.name='process-engine',
        schema.name='public',
        slot.name='risingwave_camunda_slot',
        publication.name='risingwave_camunda_pub',
        publication.create.enable='false',
        ssl.mode='require'
    );
{% endif %}
