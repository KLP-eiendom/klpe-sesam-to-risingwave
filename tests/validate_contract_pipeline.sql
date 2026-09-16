-- ============================================================================
-- Contract Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Contract Data Pipeline deployment and
-- data quality across D365 and Leko sources.
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_contract_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Contract Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Source Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Contract Source Record Count Validation'
\echo ''

SELECT
    'stg_d365_kontrakt' AS source,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 1000 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM stg_d365_kontrakt
UNION ALL
SELECT
    'stg_leko_kontrakt',
    COUNT(*),
    CASE
        WHEN COUNT(*) > 0 THEN '✓ PASS'
        ELSE '⚠ NO DATA (Worker active?)'
    END
FROM stg_leko_kontrakt;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Contract Statistics
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Contract Life Cycle Statistics'
\echo ''

SELECT
    COUNT(*) AS total_contracts,
    COUNT(CASE WHEN til_dato > NOW() OR til_dato IS NULL THEN 1 END) AS active_contracts,
    COUNT(CASE WHEN til_dato <= NOW() THEN 1 END) AS expired_contracts,
    COUNT(CASE WHEN kontrakt_status = 'Opphørt' THEN 1 END) AS terminated_status
FROM stg_d365_kontrakt;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Date Sanity Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Date Sanity Validation'
\echo ''

SELECT
    kontrakt_id,
    fra_dato,
    til_dato,
    'Start after End' AS issue
FROM stg_d365_kontrakt
WHERE fra_dato > til_dato
UNION ALL
SELECT
    kontrakt_id,
    fra_dato,
    til_dato,
    'Invalid Start Date'
FROM stg_d365_kontrakt
WHERE fra_dato < '1900-01-01' OR fra_dato > '2100-01-01';

\echo ''

-- -----------------------------------------------------------------------------
-- Test 4: Linkage Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 4: Linkage Validation (Orphan Checks)'
\echo ''

SELECT
    'Contracts without Customer' AS check_name,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '⚠ WARNING' END AS status
FROM stg_d365_kontrakt
WHERE kunde_id IS NULL
UNION ALL
SELECT
    'Contracts without Building',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '⚠ WARNING' END
FROM stg_d365_kontrakt
WHERE bygg_avdeling_id IS NULL;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 5: Real-time Sync Lag
-- -----------------------------------------------------------------------------
\echo '>>> Test 5: Real-time Sync Lag'
\echo ''

SELECT
    'd365_kontrakt' AS source,
    MAX(rw_synced_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(rw_synced_at))) / 60 AS lag_minutes
FROM stg_d365_kontrakt;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
