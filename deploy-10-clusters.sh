#!/bin/bash
# Deploy 10 vClusters with external database connector

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "Deploying 10 vClusters with Connector"
echo -e "==========================================${NC}"
echo ""

# Check if PostgreSQL is running
if ! kubectl get pod -n vcluster-db -l app=postgres &>/dev/null; then
    echo -e "${RED}Error: PostgreSQL not found in vcluster-db namespace${NC}"
    echo "Please deploy PostgreSQL first:"
    echo "  kubectl apply -f examples/external-database/postgres-values.yaml"
    exit 1
fi

# Get PostgreSQL service details
POSTGRES_HOST="postgres.vcluster-db.svc.cluster.local"
POSTGRES_PORT="5432"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="postgres123"

echo -e "${YELLOW}Using PostgreSQL: ${POSTGRES_HOST}:${POSTGRES_PORT}${NC}"
echo ""

# Deploy 10 vClusters
for i in {1..10}; do
    NAMESPACE="vcluster-${i}"
    VCLUSTER_NAME="vc-${i}"
    
    echo -e "${GREEN}[${i}/10] Deploying ${VCLUSTER_NAME} in namespace ${NAMESPACE}...${NC}"
    
    # Create namespace
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Create connector secret
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connector
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  type: "postgres"
  host: "${POSTGRES_HOST}"
  port: "${POSTGRES_PORT}"
  adminUser: "${POSTGRES_USER}"
  adminPassword: "${POSTGRES_PASSWORD}"
  sslMode: "disable"
EOF
    
    # Deploy vCluster
    vcluster create ${VCLUSTER_NAME} \
      --namespace ${NAMESPACE} \
      --values examples/external-database/connector-postgres-values.yaml \
      --connect=false
    
    echo -e "${GREEN}✓ ${VCLUSTER_NAME} deployment initiated${NC}"
    echo ""
done

echo -e "${GREEN}=========================================="
echo "All 10 vClusters Deployed!"
echo -e "==========================================${NC}"
echo ""
echo "Waiting for pods to be ready..."
echo ""

# Wait for all pods
for i in {1..10}; do
    NAMESPACE="vcluster-${i}"
    VCLUSTER_NAME="vc-${i}"
    
    echo -n "Waiting for ${VCLUSTER_NAME}... "
    kubectl wait --namespace ${NAMESPACE} \
      --for=condition=ready pod \
      -l app=vcluster \
      --timeout=300s &>/dev/null && \
      echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
done

echo ""
echo -e "${GREEN}=========================================="
echo "Deployment Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Summary:"
echo "  - 10 namespaces created"
echo "  - 10 vClusters deployed"
echo "  - 10 databases will be auto-provisioned"
echo ""
echo "Check status:"
echo "  kubectl get pods -A | grep vcluster"
echo ""
echo "Check databases:"
echo "  kubectl exec -n vcluster-db deploy/postgres -- psql -U postgres -c \"SELECT datname FROM pg_database WHERE datname LIKE 'vcluster%';\""
echo ""
echo "Connect to a vCluster:"
echo "  vcluster connect vc-1 --namespace vcluster-1"
echo ""

