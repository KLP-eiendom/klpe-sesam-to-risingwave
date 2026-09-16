#!/bin/bash
# Setup environment variables for RisingWave SQL scripts

set -e

# Environment selection
ENVIRONMENT=${1:-dev}

echo "Setting up environment variables for: $ENVIRONMENT"
echo

# GCP Project configuration
case $ENVIRONMENT in
  dev)
    PROJECT_ID="example-project-dev"
    KUBERNETES_CONTEXT="gke_example-project-dev_europe-north1_cluster-dev"
    ;;
  test)
    PROJECT_ID="example-project-test"
    KUBERNETES_CONTEXT="gke_example-project-test_europe-north1_cluster-test"
    ;;
  prod)
    PROJECT_ID="example-project-prod"
    KUBERNETES_CONTEXT="gke_example-project-prod_europe-north1_cluster-prod"
    ;;
  *)
    echo "Error: Invalid environment. Use: dev, test, or prod"
    exit 1
    ;;
esac

echo "Project: $PROJECT_ID"
echo "Kubernetes context: $KUBERNETES_CONTEXT"
echo

# Set kubectl context
kubectl config use-context "$KUBERNETES_CONTEXT"

# Get database credentials from Kubernetes secrets
echo "Retrieving database credentials from Kubernetes secrets..."

KUNDEPORTAL_MYSQL_PASSWORD=$(kubectl get secret kundeportal-db-credentials -o jsonpath='{.data.password}' | base64 -d)
FORVALTER_MYSQL_PASSWORD=$(kubectl get secret forvalter-db-credentials -o jsonpath='{.data.password}' | base64 -d)

# Database hosts (from Cloud SQL)
KUNDEPORTAL_MYSQL_HOST=$(kubectl get secret kundeportal-db-credentials -o jsonpath='{.data.host}' | base64 -d || echo "localhost")
FORVALTER_MYSQL_HOST=$(kubectl get secret forvalter-db-credentials -o jsonpath='{.data.host}' | base64 -d || echo "localhost")

# Create .env file for sourcing
cat > ../risingwave_${ENVIRONMENT}.env <<EOF
# RisingWave Environment Configuration - $ENVIRONMENT
# Generated: $(date)

# GCP Project
export GCP_PROJECT_ID="$PROJECT_ID"
export ENVIRONMENT="$ENVIRONMENT"

# Kundeportal Database
export KUNDEPORTAL_MYSQL_HOST="$KUNDEPORTAL_MYSQL_HOST"
export KUNDEPORTAL_MYSQL_USER="risingwave_cdc"
export KUNDEPORTAL_MYSQL_PASSWORD="$KUNDEPORTAL_MYSQL_PASSWORD"
export KUNDEPORTAL_MYSQL_DB="kundeportal-db-$ENVIRONMENT"

# Forvalter Database
export FORVALTER_MYSQL_HOST="$FORVALTER_MYSQL_HOST"
export FORVALTER_MYSQL_USER="risingwave_writer"
export FORVALTER_MYSQL_PASSWORD="$FORVALTER_MYSQL_PASSWORD"
export FORVALTER_MYSQL_DB="forvalter-db-$ENVIRONMENT"

# RisingWave Frontend
export RISINGWAVE_HOST="localhost"
export RISINGWAVE_PORT="4566"
export RISINGWAVE_DATABASE="dev"
export RISINGWAVE_USER="root"

# GCS Configuration
export GCS_BIGQUERY_STAGING_BUCKET="klpe_${ENVIRONMENT}_workarea"

# BigQuery Configuration
export BIGQUERY_DATASET="kdi_datahub"
EOF

echo
echo "✓ Environment file created: risingwave_${ENVIRONMENT}.env"
echo
echo "To use these variables:"
echo "  source ../risingwave_${ENVIRONMENT}.env"
echo
echo "Then connect to RisingWave:"
echo "  kubectl port-forward svc/risingwave-frontend-service 4566:4566"
echo "  psql -h \$RISINGWAVE_HOST -p \$RISINGWAVE_PORT -d \$RISINGWAVE_DATABASE -U \$RISINGWAVE_USER"
echo

# Create psql variable file
cat > ../risingwave_${ENVIRONMENT}.psqlrc <<EOF
-- RisingWave psql variables - $ENVIRONMENT
-- Generated: $(date)
-- Usage: psql -h localhost -p 4566 -d dev -U root -f risingwave_${ENVIRONMENT}.psqlrc

\\set KUNDEPORTAL_MYSQL_HOST '$KUNDEPORTAL_MYSQL_HOST'
\\set KUNDEPORTAL_MYSQL_USER 'risingwave_cdc'
\\set KUNDEPORTAL_MYSQL_PASSWORD '$KUNDEPORTAL_MYSQL_PASSWORD'
\\set KUNDEPORTAL_MYSQL_DB 'kundeportal-db-$ENVIRONMENT'

\\set FORVALTER_MYSQL_HOST '$FORVALTER_MYSQL_HOST'
\\set FORVALTER_MYSQL_USER 'risingwave_writer'
\\set FORVALTER_MYSQL_PASSWORD '$FORVALTER_MYSQL_PASSWORD'
\\set FORVALTER_MYSQL_DB 'forvalter-db-$ENVIRONMENT'

\\set GCS_BIGQUERY_STAGING_BUCKET 'klpe_${ENVIRONMENT}_workarea'

\\echo 'RisingWave variables loaded for environment: $ENVIRONMENT'
\\echo 'Available variables: KUNDEPORTAL_MYSQL_*, FORVALTER_MYSQL_*, GCS_BIGQUERY_STAGING_BUCKET'
EOF

echo "✓ psql variable file created: risingwave_${ENVIRONMENT}.psqlrc"
echo
echo "To load variables in psql:"
echo "  \\i risingwave_${ENVIRONMENT}.psqlrc"
echo
