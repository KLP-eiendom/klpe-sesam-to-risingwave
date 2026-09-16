-- ============================================================================
-- Sale Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Global Sale Pipeline deployment and
-- data quality across SuperOffice poller and real-time webhook sources.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_sale_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Sale Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Source Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Sale Source Record Count Validation'
\echo ''

SELECT
    'stg_superoffice_sale' AS source,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 100 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM stg_superoffice_sale
UNION ALL
SELECT
    'stg_superoffice_salesimple',
    COUNT(*),
    CASE
        WHEN COUNT(*) > 0 THEN '✓ PASS'
        ELSE '⚠ NO DATA (Webhooks received?)'
    END
FROM stg_superoffice_salesimple
ORDER BY source;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Global Sale Merge Statistics
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Global Sale Merge Statistics'
\echo ''

SELECT
    COUNT(*) AS total_sales,
    COUNT(CASE WHEN _source = 'poller' THEN 1 END) AS from_poller,
    COUNT(CASE WHEN _source = 'webhook' THEN 1 END) AS from_webhook,
    ROUND(COUNT(CASE WHEN _source = 'webhook' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS real_time_pct
FROM mrt_global_sale;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Data Quality (Critical Fields)
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Data Quality (Critical Fields)'
\echo ''

SELECT
    'Missing Sale ID' AS issue,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM mrt_global_sale
WHERE saleId IS NULL
UNION ALL
SELECT
    'Missing Amount',
    COUNT(*),
    CASE WHEN COUNT(*) < (SELECT COUNT(*) * 0.1 FROM mrt_global_sale) THEN '✓ PASS' ELSE '⚠ WARNING' END
FROM mrt_global_sale
WHERE amount IS NULL
UNION ALL
SELECT
    'Negative Amount',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '⚠ WARNING' END
FROM mrt_global_sale
WHERE amount < 0;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 4: Sink Verification
-- -----------------------------------------------------------------------------
\echo '>>> Test 4: Sink Verification'
\echo ''

SELECT
    sink_name,
    CASE WHEN sink_name IS NOT NULL THEN '✓ DEPLOYED' ELSE '✗ MISSING' END AS status
FROM rw_catalog.rw_sinks
WHERE sink_name LIKE '%sale%'
ORDER BY sink_name;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 5: Real-time Sync Lag
-- -----------------------------------------------------------------------------
\echo '>>> Test 5: Real-time Sync Lag'
\echo ''

SELECT
    'stg_superoffice_sale' AS source,
    MAX(rw_synced_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(rw_synced_at))) / 60 AS lag_minutes
FROM stg_superoffice_sale;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
