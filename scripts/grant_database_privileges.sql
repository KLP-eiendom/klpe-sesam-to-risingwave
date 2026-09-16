-- Setup privileges for a new "risingwave" database (e.g. 'ci')
-- Run this as an administrator (e.g. 'root' or 'postgres' user)

-- 1. Ensure the user exists (if not already created)
-- CREATE USER "risingwave" WITH PASSWORD 'your_password';

-- 2. Grant privileges on the database level
-- This allows the user to connect to the database and create new schemas if needed
GRANT CONNECT, CREATE ON DATABASE ci TO "risingwave";

-- 3. Grant privileges on the public schema
-- This is where dbt models are typically created. 
-- IMPORTANT: You must be connected to the 'ci' database when running these commands.
-- psql -d ci -f grant_database_privileges.sql
