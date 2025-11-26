#!/bin/bash
set -e

CLUSTER_NAME="test-sleep"
NAMESPACE="test-sleep"

echo "Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "Creating PostgreSQL connector secret..."
kubectl apply -f connector-secret.yaml

echo "Creating vCluster with sleep mode enabled..."
vcluster create $CLUSTER_NAME \
  -f test-sleep-mode-postgres.yaml \
  -n $NAMESPACE \
  --upgrade

echo ""
echo "vCluster '$CLUSTER_NAME' created successfully!"
echo ""
echo "To check sleep mode status:"
echo "  kubectl get statefulset -n $NAMESPACE $CLUSTER_NAME -o jsonpath='{.metadata.annotations.vcluster\.loft\.sh/last-activity}'"
echo ""
echo "To test sleep mode:"
echo "  1. Wait 5 minutes without making API calls"
echo "  2. Check if vCluster is paused: vcluster list"
echo "  3. Resume manually: vcluster resume $CLUSTER_NAME -n $NAMESPACE"
