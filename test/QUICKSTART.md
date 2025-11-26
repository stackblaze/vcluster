# Quick Start: Test PostgreSQL Connector with Podman

Follow these steps to test the External Database Connector implementation.

## Step 1: Deploy PostgreSQL

```bash
cd /home/linux/vcluster/test
./postgres-podman-setup.sh
```

**Expected output:**
```
==========================================
PostgreSQL Setup for vCluster Testing
==========================================
✓ PostgreSQL container started
✓ PostgreSQL is ready!
==========================================
PostgreSQL Setup Complete!
==========================================
```

## Step 2: Verify PostgreSQL is Running

```bash
# Check container status
podman ps | grep vcluster-postgres

# Test connection
podman exec -it vcluster-postgres psql -U postgres -c "SELECT version();"
```

## Step 3: Test Database Provisioning (Quick Test)

```bash
./manual-test-connector.sh
```

This tests the core database provisioning logic without creating a vCluster.

**Expected output:**
```
✓ PostgreSQL is running
✓ Database created
✓ User created
✓ Privileges granted
✓ Database verified
✓ User verified
✓ Connection successful
✓ Table operations successful
```

## Step 4: Test with Real vCluster (Full Integration)

**Note:** This requires kubectl and vcluster CLI to be configured.

```bash
./test-connector-postgres.sh
```

**Expected output:**
```
✓ PostgreSQL is running
✓ Connector secret created
✓ vCluster created
✓ Database auto-provisioned
✓ Credentials secret created
✓ vCluster is functional
```

## Step 5: Verify Everything Works

### Check databases created

```bash
podman exec vcluster-postgres psql -U postgres -c "\l" | grep vcluster
```

You should see databases like:
- `vcluster_manual_test_abc123` (from manual test)
- `vcluster_test_postgres_xyz789` (from vCluster test)

### Check users created

```bash
podman exec vcluster-postgres psql -U postgres -c "\du" | grep vcluster
```

### Check Kine tables

```bash
# Connect to the vCluster database
podman exec -it vcluster-postgres psql -U postgres

# In psql:
\c vcluster_test_postgres_<hash>
\dt

# You should see Kine tables
```

### Check credentials secret

```bash
kubectl get secret vc-db-test-postgres -n vcluster-test-postgres -o yaml
```

## Cleanup

### Remove test vCluster

```bash
vcluster delete test-postgres
kubectl delete secret postgres-connector-test
```

### Stop PostgreSQL

```bash
podman stop vcluster-postgres
```

### Remove PostgreSQL completely

```bash
podman rm -f vcluster-postgres
podman volume rm vcluster-postgres-data
```

## Troubleshooting

### PostgreSQL won't start

```bash
# Check if port 5432 is already in use
ss -tulpn | grep 5432

# Use a different port
podman run -d --name vcluster-postgres \
  -e POSTGRES_PASSWORD=vcluster-test-password \
  -p 5433:5432 \
  docker.io/library/postgres:15
```

### vCluster can't connect to localhost

If vCluster is in Kubernetes and can't reach `localhost:5432`, you have two options:

**Option A: Deploy PostgreSQL in Kubernetes**

```bash
kubectl create namespace vcluster-db
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: vcluster-db
spec:
  ports:
  - port: 5432
  selector:
    app: postgres
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: vcluster-db
spec:
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
          value: vcluster-test-password
        ports:
        - containerPort: 5432
EOF

# Then update connector secret to use:
# host: "postgres.vcluster-db.svc.cluster.local"
```

**Option B: Use host.containers.internal**

Update the connector secret:
```yaml
stringData:
  host: "host.containers.internal"  # or "host.docker.internal"
```

## What's Next?

After successful testing:

1. ✅ The connector implementation works!
2. Try creating multiple vClusters to see multi-tenancy
3. Test with MySQL using similar scripts
4. Review the implementation code
5. Deploy in your production environment

## Summary

You've successfully tested:
- ✅ PostgreSQL deployment with Podman
- ✅ Database provisioning logic
- ✅ User creation and permissions
- ✅ Connector secret configuration
- ✅ vCluster integration
- ✅ Automatic credential management

The External Database Connector is ready for production use! 🎉

