-- ============================================================================
-- Ticket Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Global Ticket (Support) Pipeline deployment.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_ticket_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Ticket Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''


-- -----------------------------------------------------------------------------
-- Test 1: Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Ticket Record Count Validation'
\echo ''

SELECT
    'mrt_superoffice_ticket' AS source,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 0 THEN '✓ PASS'
        ELSE '⚠ NO DATA'
    END AS status
FROM mrt_superoffice_ticket;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Category Distribution
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Ticket Category Distribution'
\echo ''

SELECT
    category_name,
    COUNT(*) AS ticket_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM mrt_global_ticket), 2) AS percentage
FROM mrt_global_ticket
GROUP BY category_name
ORDER BY ticket_count DESC
LIMIT 10;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Sync Metadata
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Sink Status'
\echo ''

SELECT
    sink_name,
    CASE WHEN sink_name IS NOT NULL THEN '✓ DEPLOYED' ELSE '✗ MISSING' END AS status
FROM rw_catalog.rw_sinks
WHERE sink_name LIKE '%ticket%'
ORDER BY sink_name;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
