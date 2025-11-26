# Quick Deploy vCluster with External Database on k3s

## Prerequisites
✅ k3s cluster running
✅ Custom vCluster image loaded: `vcluster-custom:connector-test`

## Step 1: Deploy PostgreSQL for Testing

```bash
# Create namespace
kubectl create namespace vcluster-db

# Deploy PostgreSQL
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init
  namespace: vcluster-db
data:
  init.sql: |
    -- This will be handled by the connector auto-provisioning
    -- Just create the admin user
    CREATE USER vcluster_admin WITH PASSWORD 'admin123' CREATEDB CREATEROLE;
---
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
        volumeMounts:
        - name: init
          mountPath: /docker-entrypoint-initdb.d
      volumes:
      - name: init
        configMap:
          name: postgres-init
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

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n vcluster-db --timeout=60s
```

## Step 2: Create vCluster Namespace and Secret

```bash
# Create namespace for vCluster
kubectl create namespace vcluster

# Create the connector secret
kubectl apply -f /home/linux/vcluster/examples/external-database/connector-postgres-secret.yaml
```

## Step 3: Deploy vCluster with Connector

```bash
cd /home/linux/vcluster

# Deploy vCluster with your custom image and connector configuration
helm install my-vcluster ./chart \
  --namespace vcluster \
  --set controlPlane.distro.k8s.enabled=true \
  --set controlPlane.backingStore.externalDatabase.enabled=true \
  --set controlPlane.advanced.virtualScheduler.enabled=false \
  --set image=vcluster-custom:connector-test \
  --set defaultImageRegistry="" \
  --set sync.toHost.pods.enabled=true \
  -f examples/external-database/connector-postgres-values.yaml

# Watch the deployment
kubectl get pods -n vcluster -w
```

## Step 4: Verify the Connector

```bash
# Check vCluster logs to see connector in action
kubectl logs -n vcluster -l app=vcluster -f

# You should see logs like:
# "Connecting to PostgreSQL connector..."
# "Auto-provisioning database: vcluster_my-vcluster_..."
# "Database and user created successfully"
# "Starting Kine with external database..."
```

## Step 5: Connect to vCluster

```bash
# Get the vCluster kubeconfig
kubectl get secret vc-my-vcluster -n vcluster -o jsonpath='{.data.config}' | base64 -d > /tmp/vcluster-kubeconfig

# Use it
export KUBECONFIG=/tmp/vcluster-kubeconfig
kubectl get nodes

# Test creating resources
kubectl create deployment nginx --image=nginx
kubectl get pods
```

## Verify Database Auto-Provisioning

```bash
# Connect to PostgreSQL and check
kubectl exec -it -n vcluster-db deployment/postgres -- psql -U postgres -c "\l"

# You should see a database like: vcluster_my-vcluster_xxxxx
# And a user: vcluster_my-vcluster_xxxxx
```

## Cleanup

```bash
# Delete vCluster
helm uninstall my-vcluster -n vcluster

# Delete PostgreSQL
kubectl delete namespace vcluster-db

# Delete vCluster namespace
kubectl delete namespace vcluster
```

## Troubleshooting

### Check vCluster logs:
```bash
kubectl logs -n vcluster -l app=vcluster --tail=100
```

### Check if connector secret exists:
```bash
kubectl get secret postgres-connector-credentials -n vcluster
```

### Check PostgreSQL connectivity:
```bash
kubectl exec -it -n vcluster-db deployment/postgres -- psql -U postgres -c "SELECT version();"
```

### Common Issues:

1. **Image pull error**: Make sure image is in k3s:
   ```bash
   sudo k3s crictl images | grep vcluster-custom
   ```

2. **Connector fails**: Check secret format and PostgreSQL accessibility

3. **Database not created**: Check vCluster logs for connector errors

## Next Steps

Once working, you can:
- Test with MySQL connector (use connector-mysql-values.yaml)
- Test direct dataSource mode (use postgres-values.yaml)
- Deploy multiple vClusters sharing the same PostgreSQL
- Test connection pooling and health checks

