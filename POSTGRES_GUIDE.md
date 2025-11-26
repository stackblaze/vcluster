# vCluster with PostgreSQL External Database

Quick guide to create and delete vClusters with PostgreSQL connector.

## Prerequisites

- PostgreSQL running and accessible
- vCluster CLI installed
- Kubernetes cluster (k3s/k8s)

## Create vCluster with PostgreSQL

1. **Deploy PostgreSQL** (if not already running):
```bash
kubectl create namespace vcluster-db
kubectl apply -f examples/external-database/postgres-values.yaml
```

2. **Create connector secret**:
```bash
kubectl create namespace my-vcluster
kubectl create secret generic postgres-connector \
  --from-literal=type=postgres \
  --from-literal=host=postgres.vcluster-db.svc.cluster.local \
  --from-literal=port=5432 \
  --from-literal=adminUser=postgres \
  --from-literal=adminPassword=postgres123 \
  --from-literal=sslMode=disable \
  -n my-vcluster
```

3. **Deploy vCluster**:
```bash
vcluster create my-vcluster \
  --namespace my-vcluster \
  --values examples/external-database/connector-postgres-values.yaml
```

The connector will automatically:
- Create a new database (e.g., `vcluster_my_vcluster_abc123`)
- Create a new user with access only to that database
- Store credentials in a secret (`vc-db-my-vcluster`)

## Delete vCluster

```bash
vcluster delete my-vcluster --namespace my-vcluster
```

The database and user are **automatically cleaned up** when you delete the vCluster.

To keep the database, use:
```bash
vcluster delete my-vcluster --namespace my-vcluster --keep-database
```

## Verify

**Check databases:**
```bash
kubectl exec -n vcluster-db deploy/postgres -- psql -U postgres -c "SELECT datname FROM pg_database WHERE datname LIKE 'vcluster%';"
```

**Connect to vCluster:**
```bash
vcluster connect my-vcluster --namespace my-vcluster
```

