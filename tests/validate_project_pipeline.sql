-- ============================================================================
-- Project Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Global Project Pipeline deployment and
-- data quality across SuperOffice poller and real-time webhook sources.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_project_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Project Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Source Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Project Source Record Count Validation'
\echo ''

SELECT
    'stg_superoffice_project' AS source,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 100 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM stg_superoffice_project
UNION ALL
SELECT
    'stg_superoffice_projectsimple',
    COUNT(*),
    CASE
        WHEN COUNT(*) > 0 THEN '✓ PASS'
        ELSE '⚠ NO DATA (Webhooks received?)'
    END
FROM stg_superoffice_projectsimple
ORDER BY source;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Global Project Merge Statistics
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Global Project Merge Statistics'
\echo ''

SELECT
    COUNT(*) AS total_projects,
    COUNT(CASE WHEN _source = 'poller' THEN 1 END) AS from_poller,
    COUNT(CASE WHEN _source = 'webhook' THEN 1 END) AS from_webhook
FROM mrt_global_project;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Data Quality (Critical Fields)
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Data Quality (Critical Fields)'
\echo ''

SELECT
    'Missing Project ID' AS issue,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM mrt_global_project
WHERE projectId IS NULL
UNION ALL
SELECT
    'Missing Name',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END
FROM mrt_global_project
WHERE name IS NULL OR name = '';

\echo ''

-- -----------------------------------------------------------------------------
-- Test 4: Real-time Sync Lag
-- -----------------------------------------------------------------------------
\echo '>>> Test 4: Real-time Sync Lag'
\echo ''

SELECT
    'stg_superoffice_project' AS source,
    MAX(rw_synced_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(rw_synced_at))) / 60 AS lag_minutes
FROM stg_superoffice_project;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
