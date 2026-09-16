#!/bin/bash
# scripts/rw-connect.sh — Port-forward RisingWave UI ports to localhost
#
# Forwards:
#   4566 → SQL frontend  (psql / dbt)
#   5691 → Dashboard     (http://localhost:5691)
#   8020 → Console       (http://localhost:8020)
#
# Usage:
#   ./scripts/rw-connect.sh           # connect to dev (default)
#   ./scripts/rw-connect.sh dev
#   ./scripts/rw-connect.sh test
#   ./scripts/rw-connect.sh prod
#
# Press Ctrl+C to stop all port-forwards.

set -euo pipefail

ENV="${1:-dev}"

case "$ENV" in
  dev)
    GKE_CLUSTER="cluster-dev"
    GKE_PROJECT="example-project-dev"
    ;;
  test)
    GKE_CLUSTER="cluster-test"
    GKE_PROJECT="example-project-test"
    ;;
  prod)
    GKE_CLUSTER="cluster-prod"
    GKE_PROJECT="example-project-prod"
    ;;
  *)
    echo "ERROR: unknown environment '$ENV'. Use: dev | test | prod" >&2
    exit 1
    ;;
esac

# ── Ensure kubectl context ────────────────────────────────────────────────────
CONTEXT="gke_${GKE_PROJECT}_europe-north1_${GKE_CLUSTER}"
if ! kubectl config get-contexts "$CONTEXT" &>/dev/null; then
    echo "==> Fetching cluster credentials for $GKE_CLUSTER ..."
    gcloud container clusters get-credentials "$GKE_CLUSTER" \
        --project="$GKE_PROJECT" --region=europe-north1
fi
kubectl config use-context "$CONTEXT" &>/dev/null
echo "==> Context: $CONTEXT"

# ── Port-forwards ─────────────────────────────────────────────────────────────
PIDS=()

cleanup() {
    echo ""
    echo "==> Stopping port-forwards ..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT INT TERM

echo "==> Starting port-forwards ..."
kubectl port-forward svc/risingwave-frontend-service 4566:4566 -n default &>/dev/null &
PIDS+=($!)

kubectl port-forward svc/risingwave-meta-service 5691:5691 -n default &>/dev/null &
PIDS+=($!)

kubectl port-forward svc/risingwave-console-service 8020:8020 -n default &>/dev/null &
PIDS+=($!)

# Wait for all three ports to be ready
for port in 4566 5691 8020; do
    for i in $(seq 1 15); do
        if (echo > /dev/tcp/localhost/$port) 2>/dev/null; then
            break
        fi
        [ "$i" -eq 15 ] && { echo "ERROR: port $port did not open in time." >&2; exit 1; }
        sleep 1
    done
done

echo ""
echo "  RisingWave ($ENV) ready:"
echo "  SQL frontend  →  psql -h localhost -p 4566 -U root -d dev"
echo "  Dashboard     →  http://localhost:5691"
echo "  Console       →  http://localhost:8020"
echo ""
echo "  Press Ctrl+C to disconnect."
echo ""

# Keep script alive until Ctrl+C
wait "${PIDS[0]}"
