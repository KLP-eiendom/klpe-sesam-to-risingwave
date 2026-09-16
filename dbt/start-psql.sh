#!/usr/bin/env bash
# dbt/start-psql.sh — Open a psql session against the local RisingWave instance
#
# Connects to the RisingWave container started by run-test.sh / fast-test.sh.
# RisingWave exposes a PostgreSQL-compatible wire protocol on port 4566.
#
# Use this for:
#   - Inspecting staging table contents after load_test_data.py
#   - Querying mart views directly to debug transformation logic
#   - Running ad-hoc SQL to reproduce or investigate E2E failures
#
# Usage (run from the dbt/ directory):
#   ./start-psql.sh
#
# Useful queries:
#   \dt                                      -- list all tables/views
#   SELECT * FROM mrt_global_customer;
#   SELECT * FROM snk_kunder_kundeportal WHERE "Kundenummer" = '10000';
#   SELECT COUNT(*), bygg_avdeling_id FROM mrt_global_property GROUP BY 2 HAVING COUNT(*) > 1;
#
# Prerequisites:
#   - psql installed (comes with PostgreSQL client tools)
#   - RisingWave running locally (start with ./run-test.sh or ./fast-test.sh)

psql -h localhost -p 4566 -d dev -U root
