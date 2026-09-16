-- ============================================================================
-- Customer Pipeline Validation Test Suite
-- ============================================================================
-- Validates customer data across staging tables and the global customer mart.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_customer_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Customer Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Source Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Source Record Count Validation'
\echo ''

SELECT
    'stg_d365_kunde' AS source,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL - no rows'
    END AS status
FROM "stg_d365_kunde"
UNION ALL
SELECT
    'stg_kundeportal_customer',
    COUNT(*),
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL - no rows'
    END
FROM "stg_kundeportal_customer"
UNION ALL
SELECT
    'stg_superoffice_contact',
    COUNT(*),
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL - no rows'
    END
FROM "stg_superoffice_contact"
UNION ALL
SELECT
    'stg_superoffice_contactsimple',
    COUNT(*),
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL - no rows'
    END
FROM "stg_superoffice_contactsimple"
ORDER BY source;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Global Customer Mart Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Global Customer Mart Validation'
\echo ''

SELECT
    COUNT(*) AS total_global_customers,
    COUNT(kundenummer) AS with_kundenummer,
    COUNT(contactId) AS with_contact_id,
    COUNT(emailAddress) AS with_email,
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL - no rows'
    END AS status
FROM "mrt_global_customer";

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Data Completeness (Critical Fields)
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Data Completeness (Critical Fields)'
\echo ''

SELECT
    'Missing kundenummer' AS issue,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARNING' END AS status
FROM "mrt_global_customer"
WHERE kundenummer IS NULL
UNION ALL
SELECT
    'Missing navn',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARNING' END
FROM "mrt_global_customer"
WHERE navn IS NULL
UNION ALL
SELECT
    'Missing contactId',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARNING' END
FROM "mrt_global_customer"
WHERE contactId IS NULL;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 4: Sink Existence Check
-- -----------------------------------------------------------------------------
\echo '>>> Test 4: Sink Existence Check'
\echo ''

SELECT
    name AS sink_name,
    'EXISTS' AS status
FROM rw_catalog.rw_sinks
WHERE name LIKE '%customer%'
ORDER BY name;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 5: Sample Records
-- -----------------------------------------------------------------------------
\echo '>>> Test 5: Sample Records from mrt_global_customer'
\echo ''

SELECT
    kundenummer,
    COALESCE(navn, nameDepartment) AS navn,
    emailAddress,
    country,
    contactId
FROM "mrt_global_customer"
ORDER BY kundenummer
LIMIT 10;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
