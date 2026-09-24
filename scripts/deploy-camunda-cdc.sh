#!/bin/bash
# =============================================================================
# RisingWave Camunda CDC Deployment Script
# Environment: Development
# =============================================================================
# This script sets up CDC (Change Data Capture) from the Camunda PostgreSQL
# database into RisingWave for real-time process analytics.
# =============================================================================

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
SQL_DIR="${PROJECT_ROOT}/sql"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ENVIRONMENT="${ENVIRONMENT:-dev}"
GCP_PROJECT="example-project-${ENVIRONMENT}"
KUBERNETES_CONTEXT="gke_example-project-${ENVIRONMENT}_europe-north1_cluster-${ENVIRONMENT}"
RISINGWAVE_NAMESPACE="default"

# Camunda database connection is resolved at runtime from the Kubernetes secret
# (see get_camunda_credentials below) — no hostnames are hardcoded here.
CAMUNDA_DATABASE="process-engine"
CAMUNDA_USERNAME="camunda-user"
CAMUNDA_PORT="5432"

# RisingWave configuration
RISINGWAVE_FRONTEND_SERVICE="risingwave-frontend-service"
RISINGWAVE_FRONTEND_PORT="4566"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
find_psql() {
    # Check if psql is in PATH
    if command -v psql &> /dev/null; then
        echo "psql"
        return 0
    fi

    # Try common Windows PostgreSQL installation paths
    local psql_paths=(
        "/c/Program Files/PostgreSQL/18/bin/psql.exe"
        "/c/Program Files/PostgreSQL/17/bin/psql.exe"
        "/c/Program Files/PostgreSQL/16/bin/psql.exe"
        "/c/Program Files/PostgreSQL/15/bin/psql.exe"
        "/c/Program Files/pgAdmin 4/runtime/psql.exe"
    )

    for psql_path in "${psql_paths[@]}"; do
        if [ -f "$psql_path" ]; then
            echo "$psql_path"
            return 0
        fi
    done

    return 1
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi

    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check psql
    if ! command -v psql &> /dev/null; then
        log_warning "psql is not installed. You won't be able to run SQL commands directly."
    fi

    log_success "Prerequisites check passed."
}

# -----------------------------------------------------------------------------
# GCP Authentication
# -----------------------------------------------------------------------------
authenticate_gcp() {
    log_info "Authenticating with GCP project: ${GCP_PROJECT}..."

    # Try to set project, but don't fail if gcloud has issues
    if gcloud config set project "${GCP_PROJECT}" 2>/dev/null; then
        log_success "GCP authentication configured."
    else
        log_warning "Could not set GCP project via gcloud, but continuing anyway..."
    fi
}

# -----------------------------------------------------------------------------
# Kubernetes Context Setup
# -----------------------------------------------------------------------------
setup_kubernetes_context() {
    log_info "Setting up Kubernetes context: ${KUBERNETES_CONTEXT}..."

    # Check if we're already in the correct context
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")

    if [ "${CURRENT_CONTEXT}" = "${KUBERNETES_CONTEXT}" ]; then
        log_info "Already using correct Kubernetes context: ${KUBERNETES_CONTEXT}"
        log_success "Kubernetes context configured."
        return 0
    fi

    # Try to get credentials for the cluster
    if gcloud container clusters get-credentials "cluster-${ENVIRONMENT}" \
        --region europe-north1 \
        --project "${GCP_PROJECT}" 2>/dev/null; then
        kubectl config use-context "${KUBERNETES_CONTEXT}"
        log_success "Kubernetes context configured."
    else
        log_warning "Could not get cluster credentials via gcloud."
        log_info "Attempting to use current context: ${CURRENT_CONTEXT}"

        # Check if kubectl can connect
        if ! kubectl cluster-info &>/dev/null; then
            log_error "Cannot connect to Kubernetes cluster. Please configure kubectl manually."
            exit 1
        fi
        log_success "Using existing Kubernetes configuration."
    fi
}

# -----------------------------------------------------------------------------
# Retrieve Camunda Database Credentials
# -----------------------------------------------------------------------------
get_camunda_credentials() {
    log_info "Retrieving Camunda database credentials from Kubernetes secrets..."

    # Try the dedicated RisingWave CDC secret first (created by Terraform)
    if kubectl get secret risingwave-camunda-cdc-credentials &> /dev/null; then
        log_info "Using risingwave-camunda-cdc-credentials secret..."
        CAMUNDA_HOST=$(kubectl get secret risingwave-camunda-cdc-credentials \
            -o jsonpath='{.data.hostname}' | base64 --decode)
        CAMUNDA_DB_PASSWORD=$(kubectl get secret risingwave-camunda-cdc-credentials \
            -o jsonpath='{.data.password}' | base64 --decode)
        CAMUNDA_USERNAME=$(kubectl get secret risingwave-camunda-cdc-credentials \
            -o jsonpath='{.data.username}' | base64 --decode)
        CAMUNDA_DATABASE=$(kubectl get secret risingwave-camunda-cdc-credentials \
            -o jsonpath='{.data.database}' | base64 --decode)
    else
        # Fallback to cambpm-db-credentials secret
        log_info "Using cambpm-db-credentials secret (fallback)..."
        CAMUNDA_DB_PASSWORD=$(kubectl get secret cambpm-db-credentials \
            -o jsonpath='{.data.db_password}' | base64 --decode)

        CAMUNDA_DB_URL=$(kubectl get secret cambpm-db-credentials \
            -o jsonpath='{.data.db_url}' | base64 --decode)

        # Extract the IP address from the JDBC URL
        CAMUNDA_HOST=$(echo "${CAMUNDA_DB_URL}" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
    fi

    if [ -z "${CAMUNDA_DB_PASSWORD}" ]; then
        log_error "Failed to retrieve Camunda database password."
        exit 1
    fi

    log_success "Camunda credentials retrieved successfully."
    log_info "Camunda Host: ${CAMUNDA_HOST}"
    log_info "Camunda Database: ${CAMUNDA_DATABASE}"
    log_info "Camunda Username: ${CAMUNDA_USERNAME}"
}

# -----------------------------------------------------------------------------
# Check RisingWave Status
# -----------------------------------------------------------------------------
check_risingwave_status() {
    log_info "Checking RisingWave deployment status..."

    # Check if RisingWave pods are running
    RISINGWAVE_PODS=$(kubectl get pods -l app=risingwave --no-headers 2>/dev/null | wc -l)

    if [ "${RISINGWAVE_PODS}" -eq 0 ]; then
        log_error "No RisingWave pods found. Please deploy RisingWave first."
        log_info "Run: kubectl apply -f kubernetes/dev/cluster-north/risingwave-*.yml"
        exit 1
    fi

    # Check if all pods are ready
    READY_PODS=$(kubectl get pods -l app=risingwave --no-headers 2>/dev/null | grep -c "Running" || true)

    log_info "RisingWave pods: ${READY_PODS}/${RISINGWAVE_PODS} running"

    if [ "${READY_PODS}" -lt "${RISINGWAVE_PODS}" ]; then
        log_warning "Some RisingWave pods are not ready. Waiting..."
        kubectl wait --for=condition=ready pod -l app=risingwave --timeout=300s
    fi

    log_success "RisingWave is running."
}

# -----------------------------------------------------------------------------
# Create Kubernetes Secret for Camunda CDC
# -----------------------------------------------------------------------------
create_camunda_cdc_secret() {
    log_info "Creating Kubernetes secret for Camunda CDC credentials..."

    # Check if secret already exists
    if kubectl get secret risingwave-camunda-cdc-credentials &> /dev/null; then
        log_warning "Secret risingwave-camunda-cdc-credentials already exists. Updating..."
        kubectl delete secret risingwave-camunda-cdc-credentials
    fi

    kubectl create secret generic risingwave-camunda-cdc-credentials \
        --from-literal=hostname="${CAMUNDA_HOST}" \
        --from-literal=port="${CAMUNDA_PORT}" \
        --from-literal=username="${CAMUNDA_USERNAME}" \
        --from-literal=password="${CAMUNDA_DB_PASSWORD}" \
        --from-literal=database="${CAMUNDA_DATABASE}"

    kubectl label secret risingwave-camunda-cdc-credentials \
        environment="${ENVIRONMENT}" \
        application=risingwave \
        source=camunda

    log_success "Kubernetes secret created."
}

# -----------------------------------------------------------------------------
# Create Camunda CDC ConfigMap
# -----------------------------------------------------------------------------
create_camunda_cdc_configmap() {
    log_info "Creating ConfigMap for Camunda CDC configuration..."

    # Delete existing configmap if it exists
    kubectl delete configmap risingwave-camunda-cdc-config --ignore-not-found

    kubectl create configmap risingwave-camunda-cdc-config \
        --from-file=${SQL_DIR}/schemas/04_camunda_cdc_source.sql \
        --from-file=${SQL_DIR}/staging/camunda_tables.sql \
        --from-file=${SQL_DIR}/materialized_views/camunda_materialized_views.sql \
        --from-file=${SQL_DIR}/deploy_camunda.sql

    kubectl label configmap risingwave-camunda-cdc-config \
        environment="${ENVIRONMENT}" \
        application=risingwave \
        source=camunda

    log_success "ConfigMap created."
}

# -----------------------------------------------------------------------------
# Port Forward to RisingWave
# -----------------------------------------------------------------------------
start_port_forward() {
    log_info "Starting port-forward to RisingWave frontend..."

    # Kill any existing port-forward
    pkill -f "kubectl port-forward.*${RISINGWAVE_FRONTEND_PORT}" 2>/dev/null || true

    kubectl port-forward "svc/${RISINGWAVE_FRONTEND_SERVICE}" "${RISINGWAVE_FRONTEND_PORT}:${RISINGWAVE_FRONTEND_PORT}" &
    PORT_FORWARD_PID=$!

    # Wait for port-forward to be ready
    sleep 3

    if ! kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
        log_error "Failed to start port-forward."
        exit 1
    fi

    log_success "Port-forward started on localhost:${RISINGWAVE_FRONTEND_PORT}"
}

# -----------------------------------------------------------------------------
# Execute SQL Setup
# -----------------------------------------------------------------------------
execute_sql_setup() {
    log_info "Executing Camunda CDC SQL setup..."

    # Use the Camunda deployment SQL file
    DEPLOY_ALL_SQL="${SQL_DIR}/deploy_camunda.sql"

    if [ -f "${DEPLOY_ALL_SQL}" ]; then
        # Create temporary directory for SQL files with substitutions
        TEMP_DIR=$(mktemp -d)

        # Copy SQL structure
        mkdir -p "${TEMP_DIR}/schemas" "${TEMP_DIR}/staging" "${TEMP_DIR}/materialized_views"

        # Process schemas files (replace placeholders)
        sed "s/<CAMUNDA_PASSWORD>/${CAMUNDA_DB_PASSWORD}/g" "${SQL_DIR}/schemas/04_camunda_cdc_source.sql" | \
        sed "s/<CAMUNDA_HOST>/${CAMUNDA_HOST}/g" > "${TEMP_DIR}/schemas/04_camunda_cdc_source.sql"

        # Copy other files as-is
        cp "${SQL_DIR}/staging/camunda_tables.sql" "${TEMP_DIR}/staging/"
        cp "${SQL_DIR}/materialized_views/camunda_materialized_views.sql" "${TEMP_DIR}/materialized_views/"

        # Copy deployment SQL
        cp "${DEPLOY_ALL_SQL}" "${TEMP_DIR}/"

        # Find psql
        PSQL_CMD=$(find_psql)
        if [ $? -ne 0 ]; then
            log_error "psql not found. Cannot execute SQL setup."
            rm -rf "${TEMP_DIR}"
            return 1
        fi

        # Execute from temp directory
        cd "${TEMP_DIR}" && "$PSQL_CMD" -h localhost -p "${RISINGWAVE_FRONTEND_PORT}" -d dev -U root -f deploy_camunda.sql
        cd - > /dev/null

        # Clean up
        rm -rf "${TEMP_DIR}"

        log_success "CDC pipeline deployed successfully."
    else
        log_warning "Deployment SQL not found: ${DEPLOY_ALL_SQL}"
        log_info "Please run the SQL manually. See sql/deploy_camunda.sql"
    fi
}

# -----------------------------------------------------------------------------
# Print Connection Information
# -----------------------------------------------------------------------------
print_connection_info() {
    echo ""
    echo "============================================================================="
    echo "                    CAMUNDA CDC DEPLOYMENT COMPLETE"
    echo "============================================================================="
    echo ""
    echo "RisingWave Connection:"
    echo "  Host: localhost (via port-forward) or risingwave-frontend-service (in-cluster)"
    echo "  Port: ${RISINGWAVE_FRONTEND_PORT}"
    echo "  Database: dev"
    echo "  User: root"
    echo ""
    echo "Connect with psql:"
    echo "  psql -h localhost -p ${RISINGWAVE_FRONTEND_PORT} -d dev -U root"
    echo ""
    echo "RisingWave Console:"
    echo "  https://risingwave-${ENVIRONMENT}.example.com"
    echo ""
    echo "Camunda Database (Source):"
    echo "  Host: ${CAMUNDA_HOST}"
    echo "  Port: ${CAMUNDA_PORT}"
    echo "  Database: ${CAMUNDA_DATABASE}"
    echo "  User: ${CAMUNDA_USERNAME}"
    echo ""
    echo "Next Steps:"
    echo "  1. Connect to RisingWave: psql -h localhost -p ${RISINGWAVE_FRONTEND_PORT} -d dev -U root"
    echo "  2. Query system health: SELECT * FROM mv_system_health_dashboard;"
    echo "  3. View process metrics: SELECT * FROM mv_active_processes_by_definition;"
    echo "  4. Check the SQL README: cat ${SQL_DIR}/README.md"
    echo ""
    echo "============================================================================="
}

# -----------------------------------------------------------------------------
# Cleanup Function
# -----------------------------------------------------------------------------
cleanup() {
    log_info "Cleaning up..."
    pkill -f "kubectl port-forward.*${RISINGWAVE_FRONTEND_PORT}" 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================================="
    echo "       RisingWave Camunda CDC Deployment - ${ENVIRONMENT} Environment"
    echo "============================================================================="
    echo ""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env|-e)
                ENVIRONMENT="$2"
                GCP_PROJECT="example-project-${ENVIRONMENT}"
                KUBERNETES_CONTEXT="gke_example-project-${ENVIRONMENT}_europe-north1_cluster-${ENVIRONMENT}"
                shift 2
                ;;
            --skip-sql)
                SKIP_SQL=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -e, --env ENV     Set environment (dev, test, prod). Default: dev"
                echo "  --skip-sql        Skip SQL execution (create secret and configmap only)"
                echo "  -h, --help        Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    check_prerequisites
    authenticate_gcp
    setup_kubernetes_context
    check_risingwave_status
    get_camunda_credentials
    create_camunda_cdc_secret

    # Only create configmap and execute SQL if sql files exist
    if [ -d "${SQL_DIR}" ]; then
        create_camunda_cdc_configmap

        if [ "${SKIP_SQL:-false}" != "true" ]; then
            # Check if psql is available
            PSQL_CMD=$(find_psql)
            if [ $? -eq 0 ]; then
                log_info "Found psql: ${PSQL_CMD}"
                start_port_forward
                execute_sql_setup
            else
                log_warning "psql is not installed. Skipping SQL execution."
                log_info "To complete setup, install psql and run:"
                log_info "  psql -h localhost -p 4566 -d dev -U root -f ${SQL_DIR}/deploy_camunda.sql"
            fi
        fi
    else
        log_warning "SQL directory not found. Skipping SQL setup."
    fi

    print_connection_info

    log_success "Deployment complete!"
}

# Run main function
main "$@"
