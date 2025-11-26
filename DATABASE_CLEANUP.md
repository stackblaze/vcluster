# Database Cleanup on vCluster Deletion

## Overview

When using the external database connector, each vCluster automatically provisions:
- A dedicated database (e.g., `vcluster_my_vcluster_abc123`)
- A dedicated user with minimal privileges
- A credentials secret for backup/recovery

**By default, these resources are NOT deleted** when you delete the vCluster. This is intentional for data safety and backup purposes.

## Why Keep Databases by Default?

1. **Data Safety**: Prevents accidental data loss
2. **Backup/Recovery**: Allows restoring a vCluster from existing data
3. **Audit Trail**: Keeps historical data for compliance
4. **Manual Review**: Allows inspection before permanent deletion

## How to Clean Up Databases

### Option 1: Delete with Cleanup Flag

Use the `--delete-database` flag to automatically clean up the database when deleting a vCluster:

```bash
vcluster delete my-vcluster --namespace team-x --delete-database
```

This will:
1. Delete the vCluster (helm release, pods, etc.)
2. Terminate any active database connections
3. Drop the database (e.g., `vcluster_my_vcluster_abc123`)
4. Drop the database user (e.g., `vcluster_my_vcluster`)
5. Delete the credentials secret (e.g., `vc-db-my-vcluster`)

### Option 2: Manual Cleanup

If you deleted a vCluster without the `--delete-database` flag, you can manually clean up:

#### PostgreSQL

```bash
# Connect to PostgreSQL as admin
kubectl exec -n vcluster-db deploy/postgres -- psql -U postgres

# List vCluster databases
\l

# Drop database and user
DROP DATABASE vcluster_my_vcluster_abc123;
DROP USER vcluster_my_vcluster;
```

#### MySQL

```bash
# Connect to MySQL as admin
kubectl exec -n mysql-db deploy/mysql -- mysql -u root -p

# List databases
SHOW DATABASES;

# Drop database and user
DROP DATABASE vcluster_my_vcluster_abc123;
DROP USER 'vcluster_my_vcluster'@'%';
```

### Option 3: Batch Cleanup Script

Clean up all orphaned databases:

```bash
#!/bin/bash
# cleanup-orphaned-databases.sh

# Get list of running vClusters
VCLUSTERS=$(kubectl get pods -A -l app=vcluster -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.labels.release}{"\n"}{end}')

# Get list of databases
DATABASES=$(kubectl exec -n vcluster-db deploy/postgres -- psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datname LIKE 'vcluster_%'")

# Compare and find orphaned databases
for db in $DATABASES; do
  found=false
  for vc in $VCLUSTERS; do
    if [[ $db == vcluster_${vc/\//_}* ]]; then
      found=true
      break
    fi
  done
  
  if [ "$found" = false ]; then
    echo "Orphaned database found: $db"
    # Uncomment to delete:
    # kubectl exec -n vcluster-db deploy/postgres -- psql -U postgres -c "DROP DATABASE $db"
  fi
done
```

## What Gets Cleaned Up

When using `--delete-database`, the following are removed:

✅ **Database**: The entire vCluster database  
✅ **User**: The dedicated database user  
✅ **Credentials Secret**: The stored credentials  
✅ **Active Connections**: Terminated before deletion  

## What Stays

❌ **Connector Secret**: Admin credentials (shared across vClusters)  
❌ **Database Server**: PostgreSQL/MySQL server itself  
❌ **Other vCluster Databases**: Only the specified vCluster's database is deleted  

## Safety Features

1. **Explicit Flag Required**: Must use `--delete-database` flag
2. **Connection Termination**: Active connections are gracefully terminated
3. **Non-Blocking**: If database cleanup fails, vCluster deletion still succeeds
4. **Logging**: All cleanup actions are logged for audit

## Examples

### Delete with Cleanup

```bash
# Delete vCluster and its database
vcluster delete my-vcluster --namespace team-x --delete-database

# Output:
# Delete vcluster my-vcluster...
# Successfully deleted virtual cluster my-vcluster in namespace team-x
# Cleaning up external database...
# Dropping database 'vcluster_my_vcluster_8457a92d' and user 'vcluster_my_vcluster'
# Successfully cleaned up database 'vcluster_my_vcluster_8457a92d' and user 'vcluster_my_vcluster'
# Deleted credentials secret 'vc-db-my-vcluster'
# Successfully cleaned up external database
```

### Delete without Cleanup (Default)

```bash
# Delete vCluster, keep database for backup
vcluster delete my-vcluster --namespace team-x

# Output:
# Delete vcluster my-vcluster...
# Successfully deleted virtual cluster my-vcluster in namespace team-x
# (Database vcluster_my_vcluster_8457a92d is preserved)
```

### Restore from Existing Database

If you kept the database, you can restore by creating a new vCluster with the same name:

```bash
# The connector will detect the existing database and reuse it
vcluster create my-vcluster --namespace team-x \
  --values connector-postgres-values.yaml
```

## Best Practices

### Development/Testing
```bash
# Always cleanup in dev/test environments
vcluster delete test-cluster --namespace dev --delete-database
```

### Production
```bash
# Keep databases for backup in production
vcluster delete prod-cluster --namespace production

# Manual cleanup after verification
# (after backing up if needed)
kubectl exec -n db deploy/postgres -- psql -U postgres -c "DROP DATABASE vcluster_prod_cluster_abc123"
```

### Automated Cleanup
```bash
# Add to CI/CD pipeline
if [ "$ENVIRONMENT" = "dev" ]; then
  vcluster delete $CLUSTER_NAME --namespace $NAMESPACE --delete-database
else
  vcluster delete $CLUSTER_NAME --namespace $NAMESPACE
  # Manual approval required for database cleanup
fi
```

## Troubleshooting

### Cleanup Failed

If database cleanup fails, the vCluster is still deleted but the database remains:

```
Warning: Failed to cleanup external database: connection refused
```

**Solution**: Manually clean up the database using the admin credentials.

### Cannot Drop Database (Connections Active)

The cleanup automatically terminates connections, but if it fails:

```bash
# PostgreSQL: Force terminate connections
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = 'vcluster_my_vcluster_abc123';

# Then drop
DROP DATABASE vcluster_my_vcluster_abc123;
```

### Connector Secret Not Found

If the connector secret was deleted, cleanup cannot proceed:

```
Warning: Connector secret 'postgres-connector' not found, cannot cleanup database
```

**Solution**: Manually clean up using direct database admin credentials.

## Monitoring

Check for orphaned databases:

```bash
# List all vCluster databases
kubectl exec -n vcluster-db deploy/postgres -- \
  psql -U postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname LIKE 'vcluster_%'"

# List running vClusters
kubectl get pods -A -l app=vcluster

# Compare to find orphans
```

## See Also

- [External Database Setup](./examples/external-database/README.md)
- [Connector Configuration](./examples/external-database/connector-postgres-values.yaml)
- [Backup and Recovery](./docs/external-database-setup.md#backup-and-recovery)

