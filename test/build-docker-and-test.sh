#!/bin/bash
# Build Docker image with our changes and test with Kubernetes

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Build Docker Image & Test Connector"
echo "=========================================="

cd /home/linux/vcluster

# Configuration
IMAGE_NAME="vcluster-custom"
IMAGE_TAG="connector-test"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${YELLOW}Step 1: Building vCluster binary...${NC}"
if [ ! -f bin/vcluster ]; then
    echo "Binary not found, building..."
    ./test/build-and-test.sh
fi

echo -e "${YELLOW}Step 2: Building Docker image with Podman...${NC}"
podman build -t ${FULL_IMAGE} -f Dockerfile .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
    podman images | grep ${IMAGE_NAME}
else
    echo -e "${RED}✗ Failed to build Docker image${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 3: Checking if Kubernetes is available...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: kubectl is not configured or cluster is not accessible${NC}"
    echo ""
    echo "Options:"
    echo "  1. Set up a local cluster: kind create cluster"
    echo "  2. Use minikube: minikube start"
    echo "  3. Configure kubectl to access your cluster"
    exit 1
fi

echo -e "${GREEN}✓ Kubernetes cluster is accessible${NC}"
kubectl cluster-info

echo -e "${YELLOW}Step 4: Loading image to cluster...${NC}"

# Detect cluster type and load image accordingly
if kubectl get nodes -o jsonpath='{.items[0].metadata.name}' | grep -q "kind"; then
    echo "Detected kind cluster, loading image..."
    podman save ${FULL_IMAGE} | kind load image-archive /dev/stdin
elif command -v minikube &> /dev/null && minikube status &> /dev/null; then
    echo "Detected minikube cluster, loading image..."
    podman save ${FULL_IMAGE} -o /tmp/${IMAGE_NAME}.tar
    minikube image load /tmp/${IMAGE_NAME}.tar
    rm /tmp/${IMAGE_NAME}.tar
else
    echo -e "${YELLOW}⚠ Could not detect cluster type${NC}"
    echo "You may need to push the image to a registry or load it manually"
    echo ""
    echo "For kind: podman save ${FULL_IMAGE} | kind load image-archive /dev/stdin"
    echo "For minikube: minikube image load ${FULL_IMAGE}"
fi

echo -e "${YELLOW}Step 5: Creating connector secret...${NC}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connector-test
  namespace: default
type: Opaque
stringData:
  type: "postgres"
  host: "host.docker.internal"
  port: "5432"
  adminUser: "postgres"
  adminPassword: "vcluster-test-password"
  sslMode: "disable"
EOF

echo -e "${GREEN}✓ Connector secret created${NC}"

echo -e "${YELLOW}Step 6: Installing vCluster with custom image...${NC}"

# Add helm repo if not already added
helm repo add loft https://charts.loft.sh 2>/dev/null || true
helm repo update

# Install vCluster with custom image
helm install test-postgres loft/vcluster \
  --create-namespace \
  --namespace vcluster-test-postgres \
  --set image=${FULL_IMAGE} \
  --set controlPlane.backingStore.database.external.enabled=true \
  --set controlPlane.backingStore.database.external.connector=postgres-connector-test \
  --wait --timeout=5m

echo -e "${GREEN}✓ vCluster installed${NC}"

echo -e "${YELLOW}Step 7: Checking vCluster status...${NC}"
kubectl get pods -n vcluster-test-postgres

echo -e "${YELLOW}Step 8: Checking vCluster logs for connector activity...${NC}"
echo "Looking for database provisioning logs..."
kubectl logs -n vcluster-test-postgres -l app=vcluster --tail=100 | grep -i "database\|connector\|kine\|provision" || echo "No connector logs found yet"

echo -e "${YELLOW}Step 9: Checking if database was created...${NC}"
podman exec vcluster-postgres psql -U postgres -c "\l" | grep vcluster || echo "No vCluster databases found yet"

echo -e "${YELLOW}Step 10: Checking if credentials secret was created...${NC}"
kubectl get secret -n vcluster-test-postgres | grep vc-db || echo "Credentials secret not found yet"

echo ""
echo "=========================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=========================================="
echo ""
echo "Check detailed logs:"
echo "  kubectl logs -n vcluster-test-postgres -l app=vcluster -f"
echo ""
echo "Check databases:"
echo "  podman exec vcluster-postgres psql -U postgres -c '\l'"
echo ""
echo "Check credentials:"
echo "  kubectl get secret vc-db-test-postgres -n vcluster-test-postgres -o yaml"
echo ""
echo "Clean up:"
echo "  helm uninstall test-postgres -n vcluster-test-postgres"
echo "  kubectl delete namespace vcluster-test-postgres"
echo "  kubectl delete secret postgres-connector-test"
echo ""



