-- Create PostgreSQL publication for Camunda CDC
-- Run this as camunda-user (the table owner)
--
-- Usage:
-- PGPASSWORD='password' psql -h <camunda-db-host> -p 5432 -U camunda-user -d process-engine -f create_publication.sql

-- Drop existing publication if it exists
DROP PUBLICATION IF EXISTS risingwave_camunda_pub;

-- Create publication for all Camunda tables
CREATE PUBLICATION risingwave_camunda_pub FOR ALL TABLES;

-- Grant permission to risingwave-cdc-user to use this publication
-- Note: In PostgreSQL, any user can use a publication if they have SELECT on the tables

-- Verify publication was created
\dRp+ risingwave_camunda_pub