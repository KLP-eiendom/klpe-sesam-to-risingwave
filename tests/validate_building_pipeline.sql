-- ============================================================================
-- Building Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Building Data Pipeline deployment and
-- data quality across all sources (D365, FDV-web) and transformations.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_building_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Building Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Source Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Building Source Record Count Validation'
\echo ''
\echo 'Checking record counts from all building data sources...'
\echo ''

SELECT
    'stg_d365_building' AS source,
    COUNT(*) AS actual_count,
    '~1,000' AS expected_range,
    CASE
        WHEN COUNT(*) > 500 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM stg_d365_building
UNION ALL
SELECT
    'stg_fdvweb_building',
    COUNT(*),
    '~1,000',
    CASE
        WHEN COUNT(*) > 500 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END
FROM stg_fdvweb_building
ORDER BY source;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Global Property Merge Statistics
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Global Property Merge Statistics'
\echo ''
\echo 'Validating mrt_global_property materialized view...'
\echo ''

SELECT
    COUNT(*) AS total_properties,
    COUNT(bygg_id) AS with_d3_building,
    COUNT(eiendnr) AS with_fdvweb_building,
    ROUND(COUNT(eiendnr) * 100.0 / COUNT(*), 2) AS fdvweb_coverage_pct
FROM mrt_global_property;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Data Completeness (Critical Fields)
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Data Completeness (Critical Fields)'
\echo ''
\echo 'Checking for missing critical building fields...'
\echo ''

SELECT
    'Missing Building ID' AS issue,
    COUNT(*) AS count,
    CASE
        WHEN COUNT(*) = 0 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM mrt_global_property
WHERE bygg_avdeling_id IS NULL
UNION ALL
SELECT
    'Missing Address (D365)',
    COUNT(*),
    CASE
        WHEN COUNT(*) < (SELECT COUNT(*) * 0.1 FROM mrt_global_property) THEN '✓ PASS'
        ELSE '⚠ WARNING'
    END
FROM mrt_global_property
WHERE b_adresse IS NULL
UNION ALL
SELECT
    'Missing Total Physical Area',
    COUNT(*),
    CASE
        WHEN COUNT(*) < (SELECT COUNT(*) * 0.2 FROM mrt_global_property) THEN '✓ PASS'
        ELSE '⚠ WARNING'
    END
FROM mrt_global_property
WHERE TotalPhysicalArea IS NULL OR TotalPhysicalArea = 0;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 4: Energy Categorization Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 4: Energy Categorization Validation'
\echo ''
\echo 'Checking energy grade distributions...'
\echo ''

-- Note: Assumes mrt_fdvweb_energy_categorization exists or joined in marts
SELECT
    energiskalaid,
    COUNT(*) AS building_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM mrt_global_property WHERE energiskalaid IS NOT NULL), 2) AS percentage
FROM mrt_global_property
WHERE energiskalaid IS NOT NULL
GROUP BY energiskalaid
ORDER BY energiskalaid;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 5: Area Aggregation Sanity Check
-- -----------------------------------------------------------------------------
\echo '>>> Test 5: Area Aggregation Sanity Check'
\echo ''
\echo 'Checking for logical area inconsistencies...'
\echo ''

SELECT
    bygg_avdeling_id,
    ba_navn,
    TotalPhysicalArea,
    TotalRentedArea,
    TotalVacantArea,
    (TotalRentedArea + TotalVacantArea) AS calculated_total,
    ABS(TotalPhysicalArea - (TotalRentedArea + TotalVacantArea)) AS discrepancy
FROM mrt_global_property
WHERE ABS(TotalPhysicalArea - (TotalRentedArea + TotalVacantArea)) > 10.0
LIMIT 10;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 6: Real-time Sync Lag
-- -----------------------------------------------------------------------------
\echo '>>> Test 6: Real-time Sync Lag'
\echo ''
\echo 'Checking data freshness for building sources...'
\echo ''

SELECT
    'd365_building' AS source,
    MAX(rw_synced_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(rw_synced_at))) / 60 AS lag_minutes
FROM stg_d365_building
UNION ALL
SELECT
    'fdvweb_building',
    MAX(rw_synced_at),
    EXTRACT(EPOCH FROM (NOW() - MAX(rw_synced_at))) / 60
FROM stg_fdvweb_building;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
