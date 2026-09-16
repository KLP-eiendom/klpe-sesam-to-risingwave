-- ============================================================================
-- Vendor Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Global Vendor (Leverandør) Pipeline deployment
-- and data quality across D365 poller and SuperOffice enrichment.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_vendor_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Vendor Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Source Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Vendor Source Record Count Validation'
\echo ''

SELECT
    'stg_d365_leverandor' AS source,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 100 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM stg_d365_leverandor;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Mart Enrollment and Enrichment
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Global Vendor Enrichment Statistics'
\echo ''

SELECT
    COUNT(*) AS total_vendors,
    COUNT(contactId) AS enriched_from_so,
    ROUND(COUNT(contactId) * 100.0 / NULLIF(COUNT(*), 0), 2) AS enrichment_pct
FROM mrt_global_leverandor;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Data Quality (Assessment Fields)
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Data Quality (Assessment & Compliance)'
\echo ''

SELECT
    'Missing Orgnr' AS issue,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) < (SELECT COUNT(*) * 0.05 FROM mrt_global_leverandor) THEN '✓ PASS' ELSE '⚠ WARNING' END AS status
FROM mrt_global_leverandor
WHERE organisasjonsnummer IS NULL
UNION ALL
SELECT
    'Blocked Vendors (leverandorsperre)',
    COUNT(*),
    'INFO'
FROM mrt_global_leverandor
WHERE leverandorsperre IS NOT NULL AND leverandorsperre != '';

\echo ''

-- -----------------------------------------------------------------------------
-- Test 4: Sink Sync Comparison
-- -----------------------------------------------------------------------------
\echo '>>> Test 4: Sink Sync Comparison'
\echo ''

SELECT
    sink_name,
    CASE WHEN sink_name IS NOT NULL THEN '✓ DEPLOYED' ELSE '✗ MISSING' END AS status
FROM rw_catalog.rw_sinks
WHERE sink_name LIKE '%leverandor%'
ORDER BY sink_name;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
