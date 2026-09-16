-- ============================================================================
-- Document Pipeline Validation Test Suite
-- ============================================================================
-- This test suite validates the Global Document Pipeline deployment and
-- multi-source merging (SuperOffice, Verified, Leko).
--
-- Usage:
--   psql -h localhost -p 4566 -d dev -U root -f tests/validate_document_pipeline.sql
-- ============================================================================

\echo '============================================================================='
\echo 'Document Pipeline Validation Test Suite'
\echo '============================================================================='
\echo ''

-- -----------------------------------------------------------------------------
-- Test 1: Record Count Validation
-- -----------------------------------------------------------------------------
\echo '>>> Test 1: Document Record Count Validation'
\echo ''

SELECT
    'stg_superoffice_document' AS source,
    COUNT(*) AS actual_count
FROM stg_superoffice_document
UNION ALL
SELECT
    'mrt_verified_document',
    COUNT(*)
FROM mrt_verified_document
UNION ALL
SELECT
    'mrt_global_document',
    COUNT(*);

\echo ''

-- -----------------------------------------------------------------------------
-- Test 2: Merge Enrichment Stats
-- -----------------------------------------------------------------------------
\echo '>>> Test 2: Global Document Enrichment Stats'
\echo ''

SELECT
    COUNT(*) AS total_documents,
    COUNT(verified_uid) AS enriched_with_verified,
    COUNT(leko_id) AS enriched_with_leko,
    COUNT(CASE WHEN unique_verified_id IS NOT NULL THEN 1 END) AS has_verified_id
FROM mrt_global_document;

\echo ''

-- -----------------------------------------------------------------------------
-- Test 3: Data Quality (Critical Fields)
-- -----------------------------------------------------------------------------
\echo '>>> Test 3: Data Quality (Critical Fields)'
\echo ''

SELECT
    'Missing Document Name' AS issue,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM mrt_global_document
WHERE name IS NULL OR name = ''
UNION ALL
SELECT
    'Missing Template Name',
    COUNT(*),
    CASE WHEN COUNT(*) < (SELECT COUNT(*) * 0.1 FROM mrt_global_document) THEN '✓ PASS' ELSE '⚠ WARNING' END
FROM mrt_global_document
WHERE documentTemplateName IS NULL;

\echo ''
\echo '============================================================================='
\echo 'Validation Complete!'
\echo '============================================================================='
