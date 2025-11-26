#!/bin/bash
# Deploy vCluster with External Database Connector on k3s

set -e

echo "=========================================="
echo "vCluster External Database Deployment"
echo "=========================================="
echo ""

# Step 1: Deploy PostgreSQL for testing
echo "Step 1: Deploying PostgreSQL..."
kubectl create namespace vcluster-db --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: vcluster-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_PASSWORD
          value: "postgres123"
        - name: POSTGRES_USER
          value: "postgres"
        - name: POSTGRES_DB
          value: "postgres"
        ports:
        - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: vcluster-db
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
EOF

echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n vcluster-db --timeout=120s

echo "✓ PostgreSQL is ready"
echo ""

# Step 2: Create vCluster namespace and secret
echo "Step 2: Creating vCluster namespace and connector secret..."
kubectl create namespace vcluster --dry-run=client -o yaml | kubectl apply -f -

# Apply the connector secret
kubectl apply -f /home/linux/vcluster/examples/external-database/connector-postgres-secret.yaml

echo "✓ Secret created"
echo ""

# Step 3: Deploy vCluster using CLI
echo "Step 3: Deploying vCluster with external database connector..."
echo ""

vcluster create my-vcluster \
  --namespace vcluster \
  --values /home/linux/vcluster/examples/external-database/connector-postgres-values.yaml \
  --set controlPlane.statefulSet.image.tag=connector-test \
  --set controlPlane.statefulSet.image.repository=vcluster-custom \
  --set controlPlane.statefulSet.imagePullPolicy=Never \
  --connect=false

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "To connect to your vCluster:"
echo "  vcluster connect my-vcluster --namespace vcluster"
echo ""
echo "To check logs:"
echo "  kubectl logs -n vcluster -l app=vcluster -f"
echo ""
echo "To verify database auto-provisioning:"
echo "  kubectl exec -it -n vcluster-db deployment/postgres -- psql -U postgres -c '\l'"
echo ""

