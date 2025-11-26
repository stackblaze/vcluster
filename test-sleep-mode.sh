#!/bin/bash
set -e

CLUSTER_NAME="test-sleep"
NAMESPACE="test-sleep"

echo "=========================================="
echo "Creating vCluster with Sleep Mode & PostgreSQL"
echo "=========================================="
echo ""

# Create namespace
echo "1. Creating namespace '$NAMESPACE'..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create connector secret in the namespace
echo ""
echo "2. Creating PostgreSQL connector secret..."
kubectl create secret generic postgres-connector \
  --from-literal=type=postgres \
  --from-literal=host=postgres.vcluster-db.svc.cluster.local \
  --from-literal=port=5432 \
  --from-literal=adminUser=postgres \
  --from-literal=adminPassword=postgres123 \
  --from-literal=sslMode=disable \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Create vCluster
echo ""
echo "3. Creating vCluster '$CLUSTER_NAME' with sleep mode enabled..."
echo "   Note: Using custom image stackblaze/vcluster:latest"
vcluster create $CLUSTER_NAME \
  -f test-sleep-mode-postgres.yaml \
  -n $NAMESPACE \
  --upgrade

echo ""
echo "=========================================="
echo "vCluster created successfully!"
echo "=========================================="
echo ""
echo "Sleep Mode Configuration:"
echo "  - Enabled: true"
echo "  - Auto-sleep after: 5 minutes of inactivity"
echo ""
echo "To check vCluster status:"
echo "  vcluster list -n $NAMESPACE"
echo ""
echo "To check last activity timestamp:"
echo "  kubectl get statefulset -n $NAMESPACE $CLUSTER_NAME -o jsonpath='{.metadata.annotations.vcluster\.loft\.sh/last-activity}' && echo"
echo ""
echo "To test sleep mode:"
echo "  1. Connect to vCluster: vcluster connect $CLUSTER_NAME -n $NAMESPACE"
echo "  2. Make some API calls (kubectl get pods, etc.)"
echo "  3. Disconnect and wait 5 minutes"
echo "  4. Check if paused: vcluster list -n $NAMESPACE"
echo "  5. Resume manually: vcluster resume $CLUSTER_NAME -n $NAMESPACE"
echo ""
echo "To delete the test cluster:"
echo "  vcluster delete $CLUSTER_NAME -n $NAMESPACE"
