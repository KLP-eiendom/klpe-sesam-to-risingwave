-- Grant SELECT privileges to risingwave-cdc-user on all Camunda tables
-- Run this with: psql -h <camunda-db-host> -p 5432 -U postgres -d process-engine -f grant_cdc_privileges.sql

-- Ensure user has REPLICATION privilege
ALTER ROLE "risingwave-cdc-user" WITH REPLICATION;

-- Grant SELECT on all existing tables in public schema
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "risingwave-cdc-user";

-- Grant SELECT on future tables in public schema (so new tables automatically get privileges)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "risingwave-cdc-user";

-- Grant USAGE on schema
GRANT USAGE ON SCHEMA public TO "risingwave-cdc-user";
