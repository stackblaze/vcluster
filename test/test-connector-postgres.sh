#!/bin/bash
# Test script for PostgreSQL Connector Auto-Provisioning
# This script tests the connector implementation with a local PostgreSQL instance

set -e

# Configuration
POSTGRES_PASSWORD="vcluster-test-password"
POSTGRES_HOST="localhost"  # Change to "host.containers.internal" if running vCluster in container
POSTGRES_PORT="5432"
CONTAINER_NAME="vcluster-postgres"
VCLUSTER_NAME="test-postgres"
NAMESPACE="default"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Testing PostgreSQL Connector"
echo "=========================================="

# Check if PostgreSQL is running
echo -e "${YELLOW}Step 1: Checking PostgreSQL...${NC}"
if ! podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}Error: PostgreSQL container is not running${NC}"
    echo "Please run: ./postgres-podman-setup.sh first"
    exit 1
fi

if ! podman exec ${CONTAINER_NAME} pg_isready -U postgres > /dev/null 2>&1; then
    echo -e "${RED}Error: PostgreSQL is not ready${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL is running${NC}"

# Create connector secret
echo -e "${YELLOW}Step 2: Creating connector secret...${NC}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connector-test
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  type: "postgres"
  host: "${POSTGRES_HOST}"
  port: "${POSTGRES_PORT}"
  adminUser: "postgres"
  adminPassword: "${POSTGRES_PASSWORD}"
  sslMode: "disable"
EOF
echo -e "${GREEN}✓ Connector secret created${NC}"

# Create vCluster with connector
echo -e "${YELLOW}Step 3: Creating vCluster with connector...${NC}"
cat > /tmp/vcluster-postgres-test.yaml <<EOF
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        connector: "postgres-connector-test"
EOF

echo "vCluster configuration:"
cat /tmp/vcluster-postgres-test.yaml
echo ""

# Note: This assumes vcluster CLI is available
if command -v vcluster &> /dev/null; then
    echo "Creating vCluster..."
    vcluster create ${VCLUSTER_NAME} -n ${NAMESPACE} -f /tmp/vcluster-postgres-test.yaml
else
    echo -e "${YELLOW}vcluster CLI not found. Please create vCluster manually with the above configuration.${NC}"
    exit 0
fi

# Wait for vCluster to be ready
echo -e "${YELLOW}Step 4: Waiting for vCluster to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=vcluster -n vcluster-${VCLUSTER_NAME} --timeout=300s

# Check if database was created
echo -e "${YELLOW}Step 5: Verifying database creation...${NC}"
echo "Databases in PostgreSQL:"
podman exec ${CONTAINER_NAME} psql -U postgres -c "\l" | grep vcluster || true

# Check if credentials secret was created
echo -e "${YELLOW}Step 6: Checking credentials secret...${NC}"
if kubectl get secret vc-db-${VCLUSTER_NAME} -n vcluster-${VCLUSTER_NAME} &> /dev/null; then
    echo -e "${GREEN}✓ Credentials secret created${NC}"
    echo "Secret contents:"
    kubectl get secret vc-db-${VCLUSTER_NAME} -n vcluster-${VCLUSTER_NAME} -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'
else
    echo -e "${RED}✗ Credentials secret not found${NC}"
fi

# Check vCluster logs
echo -e "${YELLOW}Step 7: Checking vCluster logs...${NC}"
echo "Last 20 lines of vCluster logs:"
kubectl logs -n vcluster-${VCLUSTER_NAME} -l app=vcluster --tail=20 | grep -i "database\|kine\|connector" || true

# Test vCluster functionality
echo -e "${YELLOW}Step 8: Testing vCluster functionality...${NC}"
if vcluster connect ${VCLUSTER_NAME} -n ${NAMESPACE} -- kubectl get nodes &> /dev/null; then
    echo -e "${GREEN}✓ vCluster is functional!${NC}"
else
    echo -e "${RED}✗ vCluster is not responding${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Test Complete!${NC}"
echo "=========================================="
echo ""
echo "Verify database manually:"
echo "  podman exec -it ${CONTAINER_NAME} psql -U postgres"
echo "  \\l                          # List databases"
echo "  \\du                         # List users"
echo "  \\c vcluster_<name>          # Connect to vCluster database"
echo "  \\dt                         # List tables (should see Kine tables)"
echo ""
echo "Clean up:"
echo "  vcluster delete ${VCLUSTER_NAME} -n ${NAMESPACE}"
echo "  kubectl delete secret postgres-connector-test -n ${NAMESPACE}"
echo "  podman rm -f ${CONTAINER_NAME}"
echo ""



