# External Database Examples

This directory contains example configurations for using external MySQL or PostgreSQL databases with vCluster.

## Quick Start

### Option A: Connector Auto-Provisioning (Recommended)

This method automatically creates databases and users for each vCluster.

#### MySQL with Connector

1. **Deploy MySQL in your cluster:**
```bash
kubectl create namespace vcluster-db
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: vcluster-db
spec:
  ports:
  - port: 3306
  selector:
    app: mysql
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: vcluster-db
spec:
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpassword
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-data
        emptyDir: {}
EOF
```

2. **Create connector secret:**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-connector
  namespace: default
type: Opaque
stringData:
  type: "mysql"
  host: "mysql.vcluster-db.svc.cluster.local"
  port: "3306"
  adminUser: "root"
  adminPassword: "rootpassword"
EOF
```

3. **Create vCluster (database auto-provisioned):**
```bash
vcluster create my-vcluster -f connector-mysql-values.yaml
```

4. **Verify:**
```bash
# Check vCluster is running
kubectl get pods -n vcluster-my-vcluster

# Check that credentials were saved
kubectl get secret vc-db-my-vcluster -n vcluster-my-vcluster -o yaml

# Check database was created
kubectl exec -it -n vcluster-db deployment/mysql -- \
  mysql -uroot -prootpassword -e "SHOW DATABASES LIKE 'vcluster_%';"
```

#### PostgreSQL with Connector

1. **Deploy PostgreSQL:**
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
          value: rootpassword
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-data
        emptyDir: {}
EOF
```

2. **Create connector secret:**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connector
  namespace: default
type: Opaque
stringData:
  type: "postgres"
  host: "postgres.vcluster-db.svc.cluster.local"
  port: "5432"
  adminUser: "postgres"
  adminPassword: "rootpassword"
  sslMode: "disable"
EOF
```

3. **Create vCluster (database auto-provisioned):**
```bash
vcluster create my-vcluster -f connector-postgres-values.yaml
```

### Option B: Direct DataSource (Manual Setup)

This method requires manual database setup but gives you full control.

#### MySQL

1. **Deploy MySQL in your cluster (for testing):**
```bash
kubectl create namespace vcluster-db
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: vcluster-db
spec:
  ports:
  - port: 3306
  selector:
    app: mysql
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: vcluster-db
spec:
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpassword
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-data
        emptyDir: {}
EOF
```

2. **Setup database:**
```bash
kubectl exec -it -n vcluster-db deployment/mysql -- mysql -uroot -prootpassword < mysql-setup.sql
```

3. **Create vCluster:**
```bash
# Update mysql-values.yaml with your connection details
vcluster create my-vcluster -f mysql-values.yaml
```

### PostgreSQL

1. **Deploy PostgreSQL in your cluster (for testing):**
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
          value: rootpassword
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-data
        emptyDir: {}
EOF
```

2. **Setup database:**
```bash
kubectl exec -it -n vcluster-db deployment/postgres -- psql -U postgres < postgres-setup.sql
```

3. **Create vCluster:**
```bash
# Update postgres-values.yaml with your connection details
vcluster create my-vcluster -f postgres-values.yaml
```

## Files

### Direct DataSource Mode
- `mysql-values.yaml` - vCluster configuration for MySQL
- `postgres-values.yaml` - vCluster configuration for PostgreSQL
- `mysql-setup.sql` - MySQL database setup script
- `postgres-setup.sql` - PostgreSQL database setup script

### Connector Auto-Provisioning Mode
- `connector-mysql-secret.yaml` - MySQL connector secret template
- `connector-postgres-secret.yaml` - PostgreSQL connector secret template
- `connector-mysql-values.yaml` - vCluster configuration using MySQL connector
- `connector-postgres-values.yaml` - vCluster configuration using PostgreSQL connector

## Production Considerations

For production use:

1. **Use managed databases** (AWS RDS, GCP Cloud SQL, Azure Database)
2. **Enable TLS/SSL** for all connections
3. **Store credentials in Kubernetes secrets**
4. **Use strong passwords** and rotate them regularly
5. **Enable database backups**
6. **Monitor database performance**
7. **Set up proper network policies**

## Troubleshooting

### Connection refused

Check if the database is accessible:
```bash
kubectl run -it --rm debug --image=mysql:8.0 --restart=Never -- mysql -h mysql.vcluster-db.svc.cluster.local -u vcluster_user -p
```

### Authentication failed

Verify credentials and user permissions:
```sql
-- MySQL
SHOW GRANTS FOR 'vcluster_user'@'%';

-- PostgreSQL
\du vcluster_user
```

### Check vCluster logs

```bash
kubectl logs -n vcluster-my-vcluster deployment/my-vcluster --container syncer
```

Look for messages containing "kine" or "database".

## Multiple vClusters

You can run multiple vClusters on the same database server by giving each one its own database:

```bash
# Create databases
kubectl exec -it -n vcluster-db deployment/mysql -- mysql -uroot -prootpassword -e "
CREATE DATABASE vcluster_prod;
CREATE DATABASE vcluster_staging;
GRANT ALL PRIVILEGES ON vcluster_prod.* TO 'vcluster_user'@'%';
GRANT ALL PRIVILEGES ON vcluster_staging.* TO 'vcluster_user'@'%';
FLUSH PRIVILEGES;
"

# Create vClusters
vcluster create prod -f mysql-values.yaml --set controlPlane.backingStore.database.external.dataSource="mysql://vcluster_user:your_password@tcp(mysql.vcluster-db.svc.cluster.local:3306)/vcluster_prod"

vcluster create staging -f mysql-values.yaml --set controlPlane.backingStore.database.external.dataSource="mysql://vcluster_user:your_password@tcp(mysql.vcluster-db.svc.cluster.local:3306)/vcluster_staging"
```

## See Also

- [External Database Setup Guide](../../docs/external-database-setup.md)
- [Kine Documentation](https://github.com/k3s-io/kine)

