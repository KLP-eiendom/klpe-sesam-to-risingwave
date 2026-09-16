-- Grant USAGE on RisingWave secrets to the dbt deploy user
-- Run once per environment via the RisingWave SQL editor or psql:
--   psql -h <rw-host> -p 4566 -U <admin-user> -f grant_secret_privileges.sql
--
-- Secrets are created in the RisingWave cloud console (Management → Secrets).
-- The dbt user ('risingwave') needs USAGE to reference a secret in sink/source DDL.

-- Service account key used by all Google PubSub and BigQuery sinks
-- Create the secret as the risingwave user (so it's owned by risingwave, not oauth_default):
-- CREATE SECRET risingwave_gcp_sa WITH (backend = 'meta') AS '<json-key-contents>';

GRANT USAGE ON SECRET risingwave_gcp_sa TO risingwave;


-- Setup privileges for a new RisingWave database (e.g. 'ci')
-- Run this as an administrator (e.g. 'root' or 'postgres' user)

-- 1. Ensure the user exists (if not already created)
-- CREATE USER risingwave WITH PASSWORD 'your_password';

-- 2. Grant privileges on the database level
-- This allows the user to connect to the database and create new schemas if needed
GRANT CONNECT, CREATE ON DATABASE ci TO risingwave;

-- 3. Grant privileges on the public schema
-- This is where dbt models are typically created. 
-- IMPORTANT: You must be connected to the 'ci' database when running these commands.
-- psql -d ci -f grant_database_privileges.sql

GRANT USAGE, CREATE ON SCHEMA public TO risingwave;

-- 4. Grant privileges for all existing tables/views/materialized views in the public schema
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO risingwave;
GRANT ALL PRIVILEGES ON ALL MATERIALIZED VIEWS IN SCHEMA public TO risingwave;

-- 5. Set default privileges for future objects
-- This ensures that objects created by other users are accessible, 
-- and that the dbt user has full control over what it creates.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO risingwave;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON MATERIALIZED VIEWS TO risingwave;

-- 6. (Optional) If using secrets, grant USAGE on them
-- GRANT USAGE ON SECRET risingwave_gcp_sa TO risingwave;

