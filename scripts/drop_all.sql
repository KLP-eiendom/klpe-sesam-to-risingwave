-- ─────────────────────────────────────────────────────────────────────────────
-- DYNAMIC DROP ALL
-- Generates and executes DROP statements for all objects in the public schema.
-- ─────────────────────────────────────────────────────────────────────────────

-- Disable headers and footer for clean output if run manually, 
-- but when run via 'psql -f', \gexec will handle the execution.
SET client_min_messages = 'warning';

-- 1. Drop Sinks
SELECT 'DROP SINK IF EXISTS public.' || name || ' CASCADE;' 
FROM rw_catalog.rw_sinks 
WHERE schema_id = (SELECT id FROM rw_catalog.rw_schemas WHERE name = 'public');
\gexec

-- 2. Drop Materialized Views
SELECT 'DROP MATERIALIZED VIEW IF EXISTS public.' || name || ' CASCADE;' 
FROM rw_catalog.rw_materialized_views 
WHERE schema_id = (SELECT id FROM rw_catalog.rw_schemas WHERE name = 'public');
\gexec

-- 3. Drop Views
SELECT 'DROP VIEW IF EXISTS public.' || name || ' CASCADE;' 
FROM rw_catalog.rw_views 
WHERE schema_id = (SELECT id FROM rw_catalog.rw_schemas WHERE name = 'public');
\gexec

-- 4. Drop Tables
SELECT 'DROP TABLE IF EXISTS public.' || name || ' CASCADE;' 
FROM rw_catalog.rw_tables 
WHERE schema_id = (SELECT id FROM rw_catalog.rw_schemas WHERE name = 'public');
\gexec

-- 5. Drop Sources
SELECT 'DROP SOURCE IF EXISTS public.' || name || ' CASCADE;' 
FROM rw_catalog.rw_sources 
WHERE schema_id = (SELECT id FROM rw_catalog.rw_schemas WHERE name = 'public');
\gexec
