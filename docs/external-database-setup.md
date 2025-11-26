# External Database Setup Guide

This guide explains how to configure vCluster to use an external MySQL or PostgreSQL database as the backing store instead of the default embedded SQLite database.

## Overview

vCluster can use external databases (MySQL or PostgreSQL) via [Kine](https://github.com/k3s-io/kine), which provides an etcd-compatible interface for relational databases. This is useful for:

- **High Availability**: Share a managed database across multiple vCluster instances
- **Performance**: Use optimized database servers for better performance
- **Backup & Recovery**: Leverage existing database backup solutions
- **Multi-tenancy**: Run multiple vClusters on the same database server (each with its own database)

## Prerequisites

- A MySQL 5.7+ or PostgreSQL 11+ database server
- Database credentials with appropriate permissions
- Network connectivity from vCluster pods to the database server

## Configuration Methods

### Method 1: Direct DataSource (Simple)

Provide the database connection string directly in your vCluster values:

#### MySQL Example

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "mysql://vcluster_user:password@tcp(mysql-server:3306)/vcluster_db"
```

#### PostgreSQL Example

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "postgres://vcluster_user:password@postgres-server:5432/vcluster_db?sslmode=disable"
```

### Method 2: Using Kubernetes Secrets

For better security, store credentials in a Kubernetes secret:

1. Create a secret with your database credentials:

```bash
kubectl create secret generic vcluster-db-credentials \
  --from-literal=dataSource='mysql://user:password@tcp(mysql-server:3306)/vcluster_db'
```

2. Reference the secret in your values (requires custom configuration):

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        # Note: Secret mounting requires additional configuration
```

### Method 3: Connector (Auto-Provisioning)

The connector mode automatically provisions a new database and user for your vCluster. This is ideal for multi-tenant scenarios where you want each vCluster to have its own isolated database.

**Step 1: Create a connector secret**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-connector
  namespace: default
type: Opaque
stringData:
  type: "mysql"
  host: "mysql-server.default.svc.cluster.local"
  port: "3306"
  adminUser: "root"
  adminPassword: "admin-password"
```

**Step 2: Reference the connector in vCluster values**

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        connector: "mysql-connector"
```

**What happens automatically:**
1. vCluster reads the connector secret
2. Creates a unique database (e.g., `vcluster_mycluster_abc123`)
3. Creates a user with access only to that database
4. Generates a secure random password
5. Saves credentials to a secret (`vc-db-<vcluster-name>`)
6. Starts Kine with the new database

**Benefits:**
- ✅ No manual database setup required
- ✅ Automatic credential generation
- ✅ Each vCluster gets isolated database
- ✅ Credentials stored securely in Kubernetes secrets
- ✅ Easy multi-tenant deployments

## Database Setup

### MySQL Setup

1. **Create Database and User:**

```sql
-- Create database
CREATE DATABASE vcluster_prod;

-- Create user
CREATE USER 'vcluster_user'@'%' IDENTIFIED BY 'secure_password';

-- Grant privileges
GRANT ALL PRIVILEGES ON vcluster_prod.* TO 'vcluster_user'@'%';
FLUSH PRIVILEGES;
```

2. **Connection String Format:**

```
mysql://username:password@tcp(hostname:port)/database
```

**Example:**
```
mysql://vcluster_user:mypassword@tcp(mysql.default.svc.cluster.local:3306)/vcluster_prod
```

### PostgreSQL Setup

1. **Create Database and User:**

```sql
-- Create user
CREATE USER vcluster_user WITH PASSWORD 'secure_password';

-- Create database
CREATE DATABASE vcluster_prod OWNER vcluster_user;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE vcluster_prod TO vcluster_user;
```

2. **Connection String Format:**

```
postgres://username:password@hostname:port/database?sslmode=disable
```

**Example:**
```
postgres://vcluster_user:mypassword@postgres.default.svc.cluster.local:5432/vcluster_prod?sslmode=disable
```

## TLS/SSL Configuration

### MySQL with TLS

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "mysql://user:password@tcp(mysql-server:3306)/vcluster_db"
        caFile: "/certs/ca.pem"
        certFile: "/certs/client-cert.pem"
        keyFile: "/certs/client-key.pem"
```

### PostgreSQL with TLS

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "postgres://user:password@postgres-server:5432/vcluster_db?sslmode=require"
        caFile: "/certs/ca.pem"
        certFile: "/certs/client-cert.pem"
        keyFile: "/certs/client-key.pem"
```

## Advanced Configuration

### Extra Kine Arguments

Pass additional arguments to Kine:

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "mysql://user:password@tcp(mysql-server:3306)/vcluster_db"
        extraArgs:
          - "--metrics-bind-address=:8080"
```

### AWS RDS IAM Authentication

For AWS RDS with IAM authentication:

```yaml
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "mysql://user@rds-instance.region.rds.amazonaws.com:3306/vcluster_db"
        identityProvider: "aws"
```

## Multi-Cluster Setup

You can run multiple vClusters on the same database server by giving each one its own database:

```bash
# vCluster 1
vcluster create prod --values - <<EOF
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "mysql://user:pass@tcp(mysql:3306)/vcluster_prod"
EOF

# vCluster 2
vcluster create staging --values - <<EOF
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        dataSource: "mysql://user:pass@tcp(mysql:3306)/vcluster_staging"
EOF
```

## Troubleshooting

### Connection Issues

1. **Check network connectivity:**
```bash
kubectl exec -it <vcluster-pod> -- nc -zv mysql-server 3306
```

2. **Verify credentials:**
```bash
kubectl logs <vcluster-pod> | grep -i "database\|kine"
```

3. **Check database permissions:**
```sql
-- MySQL
SHOW GRANTS FOR 'vcluster_user'@'%';

-- PostgreSQL
\du vcluster_user
```

### Performance Issues

- Ensure database server has adequate resources
- Check network latency between vCluster and database
- Monitor database connection pool settings
- Consider using connection pooling (e.g., ProxySQL for MySQL, PgBouncer for PostgreSQL)

### Migration from Embedded Database

To migrate from embedded SQLite to external database:

1. Create a backup of your vCluster
2. Deploy a new vCluster with external database configuration
3. Restore the backup to the new vCluster

## Security Best Practices

1. **Use TLS/SSL** for database connections
2. **Store credentials in secrets**, not in values files
3. **Use least-privilege database users** (only grant necessary permissions)
4. **Enable database audit logging**
5. **Regularly rotate database passwords**
6. **Use network policies** to restrict database access
7. **Consider using IAM authentication** for cloud databases (AWS RDS, GCP Cloud SQL, Azure Database)

## Performance Considerations

- **MySQL**: InnoDB storage engine recommended
- **PostgreSQL**: Tune `max_connections` and `shared_buffers`
- **Network**: Low latency between vCluster and database is critical
- **Backups**: Regular backups of the database are essential
- **Monitoring**: Monitor database metrics (connections, queries, latency)

## References

- [Kine Documentation](https://github.com/k3s-io/kine)
- [MySQL Connection String Format](https://github.com/go-sql-driver/mysql#dsn-data-source-name)
- [PostgreSQL Connection String Format](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING)

