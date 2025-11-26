# vCluster CLI with External Database Connector

Custom vCluster CLI with built-in support for external database connectors (PostgreSQL and MySQL).

## One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/stackblaze/vcluster/main/install.sh | bash
```

## Manual Install

### Linux (amd64)

```bash
curl -fsSL https://github.com/stackblaze/vcluster/raw/main/release/vcluster-linux-amd64 -o vcluster
chmod +x vcluster
sudo mv vcluster /usr/local/bin/
```

### Verify Installation

```bash
vcluster --version
```

## Features

✅ **External Database Connector**
- Automatic PostgreSQL/MySQL database provisioning
- Secure credential generation and storage
- Connection pooling and health checks

✅ **Embedded Chart**
- Uses local chart with connector support by default
- No remote dependencies

✅ **Multi-Tenancy**
- Each vCluster gets isolated database
- Automatic user and privilege management

## Quick Start

### 1. Deploy PostgreSQL (or use existing)

```bash
kubectl create namespace vcluster-db
kubectl apply -f - <<EOF
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
        image: postgres:16-alpine
        env:
        - name: POSTGRES_PASSWORD
          value: postgres123
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
EOF
```

### 2. Create Connector Secret

```bash
kubectl create namespace vcluster
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connector
  namespace: vcluster
type: Opaque
stringData:
  type: "postgres"
  host: "postgres.vcluster-db.svc.cluster.local"
  port: "5432"
  adminUser: "postgres"
  adminPassword: "postgres123"
  sslMode: "disable"
EOF
```

### 3. Create Values File

```bash
cat > connector-values.yaml <<EOF
controlPlane:
  backingStore:
    database:
      external:
        enabled: true
        connector: "postgres-connector"
        dataSource: "placeholder"
EOF
```

### 4. Deploy vCluster

```bash
vcluster create my-vcluster \
  --namespace vcluster \
  --values connector-values.yaml
```

### 5. Connect to vCluster

```bash
vcluster connect my-vcluster --namespace vcluster
```

## What Happens Automatically

1. **Reads admin credentials** from connector secret
2. **Generates unique database name** (e.g., `vcluster_my_vcluster_abc123`)
3. **Creates database** with proper encoding
4. **Creates dedicated user** with secure random password
5. **Grants privileges** to user on database
6. **Saves credentials** to secret for future reference
7. **Starts Kine** with provisioned database
8. **vCluster runs** with all state in PostgreSQL

## Docker Image

The vCluster image with connector support is also available:

```bash
docker pull stackblaze/vcluster:latest
```

## Examples

See the [examples directory](https://github.com/stackblaze/vcluster/tree/main/examples/external-database) for:
- PostgreSQL connector setup
- MySQL connector setup
- Direct connection (without connector)
- Production configurations

## Documentation

- [Full Documentation](https://github.com/stackblaze/vcluster)
- [External Database Setup Guide](https://github.com/stackblaze/vcluster/blob/main/docs/external-database-setup.md)
- [Connector Implementation](https://github.com/stackblaze/vcluster/blob/main/CONNECTOR_AUTO_PROVISIONING.md)

## Support

- GitHub Issues: https://github.com/stackblaze/vcluster/issues
- Docker Hub: https://hub.docker.com/r/stackblaze/vcluster

## License

Same as upstream vCluster (Apache 2.0)

