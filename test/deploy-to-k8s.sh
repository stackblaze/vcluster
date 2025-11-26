#!/bin/bash
# Deploy vCluster with custom image to Kubernetes

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

IMAGE_NAME="vcluster-custom"
IMAGE_TAG="connector-test"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
VCLUSTER_NAME="test-postgres"
NAMESPACE="vcluster-${VCLUSTER_NAME}"

echo "=========================================="
echo "Deploying vCluster with Connector"
echo "=========================================="

# Check if Kubernetes is available
echo -e "${YELLOW}Step 1: Checking Kubernetes cluster...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: kubectl is not configured or cluster is not accessible${NC}"
    echo ""
    echo "Please set up a Kubernetes cluster first:"
    echo "  kind create cluster --name vcluster-test"
    echo "  OR"
    echo "  minikube start"
    exit 1
fi

echo -e "${GREEN}✓ Kubernetes cluster is accessible${NC}"
kubectl cluster-info

# Check if image exists
echo -e "${YELLOW}Step 2: Checking if custom image exists...${NC}"
if ! podman images | grep -q "${IMAGE_NAME}.*${IMAGE_TAG}"; then
    echo -e "${RED}Error: Custom image not found${NC}"
    echo "Please build the image first:"
    echo "  ./build-with-podman.sh"
    exit 1
fi
echo -e "${GREEN}✓ Custom image found${NC}"

# Create connector secret
echo -e "${YELLOW}Step 3: Creating connector secret...${NC}"

# Determine PostgreSQL host based on cluster type
POSTGRES_HOST="host.docker.internal"
if kubectl get nodes -o jsonpath='{.items[0].metadata.name}' | grep -q "kind"; then
    POSTGRES_HOST="host.docker.internal"
elif command -v minikube &> /dev/null && minikube status &> /dev/null; then
    POSTGRES_HOST="host.minikube.internal"
fi

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connector-test
  namespace: default
type: Opaque
stringData:
  type: "postgres"
  host: "${POSTGRES_HOST}"
  port: "5432"
  adminUser: "postgres"
  adminPassword: "vcluster-test-password"
  sslMode: "disable"
EOF

echo -e "${GREEN}✓ Connector secret created (using host: ${POSTGRES_HOST})${NC}"

# Add helm repo
echo -e "${YELLOW}Step 4: Setting up Helm...${NC}"
helm repo add loft https://charts.loft.sh 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓ Helm repo updated${NC}"

# Install vCluster
echo -e "${YELLOW}Step 5: Installing vCluster with custom image...${NC}"
echo "This may take a few minutes..."

helm install ${VCLUSTER_NAME} loft/vcluster \
  --create-namespace \
  --namespace ${NAMESPACE} \
  --set image=${FULL_IMAGE} \
  --set imagePullPolicy=Never \
  --set controlPlane.backingStore.database.external.enabled=true \
  --set controlPlane.backingStore.database.external.connector=postgres-connector-test \
  --wait --timeout=5m

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ vCluster installed successfully${NC}"
else
    echo -e "${RED}✗ vCluster installation failed${NC}"
    echo "Check logs with: kubectl logs -n ${NAMESPACE} -l app=vcluster"
    exit 1
fi

# Wait a bit for provisioning
echo -e "${YELLOW}Waiting 10 seconds for database provisioning...${NC}"
sleep 10

# Check status
echo ""
echo "=========================================="
echo "Verification"
echo "=========================================="

echo -e "${YELLOW}vCluster Pods:${NC}"
kubectl get pods -n ${NAMESPACE}

echo ""
echo -e "${YELLOW}vCluster Logs (last 30 lines):${NC}"
kubectl logs -n ${NAMESPACE} -l app=vcluster --tail=30 | grep -i "database\|connector\|kine\|provision" || echo "No connector logs found"

echo ""
echo -e "${YELLOW}PostgreSQL Databases:${NC}"
podman exec vcluster-postgres psql -U postgres -c "\l" | grep vcluster || echo "No vCluster databases found yet"

echo ""
echo -e "${YELLOW}Credentials Secret:${NC}"
kubectl get secret -n ${NAMESPACE} | grep vc-db || echo "Credentials secret not found yet"

if kubectl get secret vc-db-${VCLUSTER_NAME} -n ${NAMESPACE} &> /dev/null; then
    echo -e "${GREEN}✓ Credentials secret exists!${NC}"
    echo "Database name:"
    kubectl get secret vc-db-${VCLUSTER_NAME} -n ${NAMESPACE} -o jsonpath='{.data.database}' | base64 -d
    echo ""
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=========================================="
echo ""
echo "Useful commands:"
echo ""
echo "View full logs:"
echo "  kubectl logs -n ${NAMESPACE} -l app=vcluster -f"
echo ""
echo "Check all databases:"
echo "  podman exec vcluster-postgres psql -U postgres -c '\l'"
echo ""
echo "View credentials:"
echo "  kubectl get secret vc-db-${VCLUSTER_NAME} -n ${NAMESPACE} -o yaml"
echo ""
echo "Connect to vCluster:"
echo "  vcluster connect ${VCLUSTER_NAME} -n ${NAMESPACE}"
echo ""
echo "Clean up:"
echo "  helm uninstall ${VCLUSTER_NAME} -n ${NAMESPACE}"
echo "  kubectl delete namespace ${NAMESPACE}"
echo "  kubectl delete secret postgres-connector-test"
echo ""



