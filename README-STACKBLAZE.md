# vCluster with External Database Connector

> **Custom fork with automatic PostgreSQL/MySQL database provisioning**

This fork adds enterprise-grade external database support with automatic provisioning to vCluster.

## 🚀 Quick Install

### One-liner Installation

```bash
curl -fsSL https://raw.githubusercontent.com/stackblaze/vcluster/main/install.sh | bash
```

### Manual Installation

```bash
# Download the binary
curl -fsSL -o vcluster https://github.com/stackblaze/vcluster/releases/latest/download/vcluster-linux-amd64

# Make it executable
chmod +x vcluster

# Move to PATH
sudo mv vcluster /usr/local/bin/
```

### Docker Image

```bash
docker pull stackblaze/vcluster:latest
```

## ✨ What's New

### External Database Connector

Automatically provision isolated databases for each vCluster:

- **Auto-provisioning**: No manual database setup required
- **Multi-tenancy**: Each vCluster gets its own database and user
- **Security**: Random passwords, minimal privileges
- **Supported**: PostgreSQL and MySQL

### How It Works

1. Provide admin database credentials via Kubernetes secret
2. vCluster automatically:
   - Creates a unique database (e.g., `vcluster_my_cluster_abc123`)
   - Creates a dedicated user with secure random password
   - Grants minimal required privileges
   - Stores credentials in a secret for backup
   - Starts with the provisioned database

## 📖 Usage

### Basic vCluster (Embedded SQLite)

```bash
vcluster create my-vcluster --namespace team-x
```

### With External PostgreSQL (Auto-Provisioned)

```bash
# 1. Create connector secret with admin credentials
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connector
  namespace: team-x
type: Opaque
stringData:
  type: "postgres"
  host: "postgres.database.svc.cluster.local"
  port: "5432"
  adminUser: "postgres"
  adminPassword: "your-admin-password"
  sslMode: "disable"
EOF

# 2. Deploy vCluster with connector
vcluster create my-vcluster \
  --namespace team-x \
  --values https://raw.githubusercontent.com/stackblaze/vcluster/main/examples/external-database/connector-postgres-values.yaml
```

### With External MySQL (Auto-Provisioned)

```bash
# 1. Create connector secret
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-connector
  namespace: team-x
type: Opaque
stringData:
  type: "mysql"
  host: "mysql.database.svc.cluster.local"
  port: "3306"
  adminUser: "root"
  adminPassword: "your-root-password"
EOF

# 2. Deploy vCluster with connector
vcluster create my-vcluster \
  --namespace team-x \
  --values https://raw.githubusercontent.com/stackblaze/vcluster/main/examples/external-database/connector-mysql-values.yaml
```

## 🎯 Features

✅ **Automatic Database Provisioning**
- Creates database and user automatically
- Generates secure random passwords
- Grants minimal required privileges

✅ **Multi-Tenancy**
- Each vCluster gets isolated database
- No manual database management
- Clean separation of data

✅ **Connection Pooling**
- Optimized database connections
- Configurable pool settings
- Health checks and auto-reconnection

✅ **Credential Management**
- Stores credentials in Kubernetes secrets
- Easy backup and recovery
- Secure password generation

✅ **Production Ready**
- Battle-tested PostgreSQL and MySQL support
- Connection pooling and health checks
- Comprehensive error handling

## 📚 Examples

See [`examples/external-database/`](./examples/external-database/) for:

- PostgreSQL connector configuration
- MySQL connector configuration
- Direct connection (pre-provisioned database)
- Helm values examples
- Complete setup guides

## 🔧 Building from Source

```bash
# Build vCluster image
docker build -t stackblaze/vcluster:latest .

# Build CLI
docker build -f Dockerfile.cli -t vcluster-cli:custom .

# Extract CLI binary
./scripts/extract-cli-binary.sh
```

## 📊 Architecture

```
┌─────────────────┐
│   vCluster CLI  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│         Kubernetes Cluster          │
│  ┌──────────────────────────────┐   │
│  │  vCluster Pod                │   │
│  │  ┌────────────────────────┐  │   │
│  │  │  Connector reads       │  │   │
│  │  │  admin credentials     │  │   │
│  │  └──────────┬─────────────┘  │   │
│  │             │                 │   │
│  │             ▼                 │   │
│  │  ┌────────────────────────┐  │   │
│  │  │  Auto-provisions:      │  │   │
│  │  │  - Database            │  │   │
│  │  │  - User                │  │   │
│  │  │  - Credentials         │  │   │
│  │  └──────────┬─────────────┘  │   │
│  │             │                 │   │
│  │             ▼                 │   │
│  │  ┌────────────────────────┐  │   │
│  │  │  Kine (etcd shim)      │  │   │
│  │  │  Connected to DB       │  │   │
│  │  └────────────────────────┘  │   │
│  └──────────────────────────────┘   │
└─────────────────┬───────────────────┘
                  │
                  ▼
         ┌─────────────────┐
         │  PostgreSQL/    │
         │  MySQL Server   │
         │                 │
         │  • vcluster_a   │
         │  • vcluster_b   │
         │  • vcluster_c   │
         └─────────────────┘
```

## 🤝 Contributing

This is a custom fork. For the original vCluster project, see:
- **Upstream**: https://github.com/loft-sh/vcluster
- **Documentation**: https://www.vcluster.com/docs

## 📝 License

Apache License 2.0 - See [LICENSE](LICENSE) for details

## 🔗 Links

- **Docker Hub**: https://hub.docker.com/r/stackblaze/vcluster
- **GitHub**: https://github.com/stackblaze/vcluster
- **Original vCluster**: https://www.vcluster.com

---

**Built with ❤️ for the vCluster community**

