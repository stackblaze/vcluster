# Testing External Database Connector with Podman

This directory contains scripts to test the External Database Connector implementation using PostgreSQL running in Podman.

## Prerequisites

- Podman installed and running
- kubectl configured with access to a Kubernetes cluster
- vcluster CLI installed (optional, for full integration test)

## Quick Start

### 1. Deploy PostgreSQL

```bash
chmod +x postgres-podman-setup.sh
./postgres-podman-setup.sh
```

This will:
- Start PostgreSQL 15 in a Podman container
- Expose it on port 5432
- Set password to `vcluster-test-password`
- Create a persistent volume for data

### 2. Test Database Provisioning (Manual)

Test the database provisioning logic without creating a vCluster:

```bash
chmod +x manual-test-connector.sh
./manual-test-connector.sh
```

This verifies:
- Database creation works
- User creation works
- Privilege granting works
- Connection with new user works
- Table operations work (simulating Kine)

### 3. Test Full Integration (with vCluster)

Test the complete connector flow with a real vCluster:

```bash
chmod +x test-connector-postgres.sh
./test-connector-postgres.sh
```

This will:
- Create a connector secret
- Create a vCluster using the connector
- Verify database was auto-provisioned
- Verify credentials secret was created
- Test vCluster functionality

## Scripts

### `postgres-podman-setup.sh`
Sets up PostgreSQL in Podman for testing.

**Usage:**
```bash
./postgres-podman-setup.sh
```

**What it does:**
- Removes existing container if present
- Starts PostgreSQL 15 container
- Waits for PostgreSQL to be ready
- Tests connection
- Displays connection details

### `manual-test-connector.sh`
Tests database provisioning logic manually.

**Usage:**
```bash
./manual-test-connector.sh
```

**What it does:**
- Creates test database
- Creates test user
- Grants privileges
- Tests connection
- Simulates Kine table operations

### `test-connector-postgres.sh`
Full integration test with vCluster.

**Usage:**
```bash
./test-connector-postgres.sh
```

**What it does:**
- Creates connector secret
- Creates vCluster with connector
- Verifies auto-provisioning
- Checks credentials secret
- Tests vCluster functionality

## Manual Testing

### Connect to PostgreSQL

```bash
# Using psql
podman exec -it vcluster-postgres psql -U postgres

# List databases
\l

# List users
\du

# Connect to a vCluster database
\c vcluster_test_abc123

# List tables (should see Kine tables)
\dt
```

### Check vCluster Logs

```bash
kubectl logs -n vcluster-test-postgres -l app=vcluster --tail=50 | grep -i "database\|kine\|connector"
```

### Verify Credentials Secret

```bash
kubectl get secret vc-db-test-postgres -n vcluster-test-postgres -o yaml
```

### Test vCluster

```bash
vcluster connect test-postgres -- kubectl get nodes
```

## Troubleshooting

### PostgreSQL not starting

```bash
# Check logs
podman logs vcluster-postgres

# Check if port is already in use
ss -tulpn | grep 5432

# Try different port
podman run -d --name vcluster-postgres -e POSTGRES_PASSWORD=test -p 5433:5432 docker.io/library/postgres:15
```

### Connection refused from vCluster

If vCluster is running in Kubernetes and can't connect to `localhost`:

1. **Option A: Use host network** (if supported)
   ```yaml
   hostNetwork: true
   ```

2. **Option B: Use host.containers.internal**
   ```yaml
   host: "host.containers.internal"
   ```

3. **Option C: Deploy PostgreSQL in Kubernetes**
   ```bash
   kubectl apply -f ../examples/external-database/postgres-deployment.yaml
   ```

### Database already exists

This is normal - the implementation is idempotent. It will use the existing database.

### Permission denied

Make sure the admin user has CREATE DATABASE and CREATE USER privileges:

```sql
-- Check privileges
\du postgres

-- Grant if needed
ALTER USER postgres WITH SUPERUSER;
```

## Cleanup

### Remove test vCluster

```bash
vcluster delete test-postgres
kubectl delete secret postgres-connector-test
kubectl delete secret vc-db-test-postgres -n vcluster-test-postgres
```

### Remove PostgreSQL container

```bash
podman rm -f vcluster-postgres
```

### Remove PostgreSQL data volume

```bash
podman volume rm vcluster-postgres-data
```

### Complete cleanup

```bash
# Stop and remove container
podman rm -f vcluster-postgres

# Remove volume
podman volume rm vcluster-postgres-data

# Remove test database (if manual test was run)
# (Already removed with container)
```

## Expected Results

### Manual Test

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

### Full Integration Test

```
✓ PostgreSQL is running
✓ Connector secret created
✓ vCluster created
✓ Database auto-provisioned
✓ Credentials secret created
✓ vCluster is functional
```

## Next Steps

After successful testing:

1. Review the implementation in `pkg/pro/external_database.go`
2. Check the connector examples in `examples/external-database/`
3. Read the documentation in `docs/external-database-setup.md`
4. Try with MySQL using similar scripts
5. Test in production environment

## Support

If you encounter issues:

1. Check PostgreSQL logs: `podman logs vcluster-postgres`
2. Check vCluster logs: `kubectl logs -n vcluster-<name> -l app=vcluster`
3. Verify network connectivity
4. Check secret contents
5. Review the troubleshooting section in the documentation

