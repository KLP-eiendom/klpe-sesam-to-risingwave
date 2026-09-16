-- ============================================================================
-- User Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Global User Pipeline deployment and
-- linkage between webhooks and polled user metadata.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_user_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'User Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: User Record Count Validation'
\echo ''

SELECT
    'stg_superoffice_user' AS source,
    COUNT(*) AS actual_count
FROM stg_superoffice_user
UNION ALL
SELECT
    'mrt_global_user',
    COUNT(*);

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Integration & Enrichment
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Global User Enrichment Stats'
\echo ''

SELECT
    COUNT(*) AS total_users,
    COUNT(contactNumber) AS with_contact_number,
    ROUND(COUNT(contactNumber) * 100.0 / NULLIF(COUNT(*), 0), 2) AS enrichment_pct
FROM mrt_global_user;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Data Quality (Critical Fields)
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Data Quality (Critical Fields)'
\echo ''

SELECT
    'Missing Email' AS issue,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM mrt_global_user
WHERE email IS NULL OR email = ''
UNION ALL
SELECT
    'Missing FullName',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END
FROM mrt_global_user
WHERE fullName IS NULL OR fullName = '';

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
