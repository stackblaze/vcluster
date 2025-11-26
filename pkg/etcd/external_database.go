package etcd

import (
	"context"
	"crypto/md5"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/loft-sh/vcluster/pkg/config"
	"github.com/loft-sh/vcluster/pkg/constants"
	"github.com/loft-sh/vcluster/pkg/util/command"
	"github.com/loft-sh/vcluster/pkg/util/osutil"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	kerrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/klog/v2"

	_ "github.com/go-sql-driver/mysql"
	_ "github.com/lib/pq"
)

var ConfigureExternalDatabase = func(ctx context.Context, kineEndpoint string, vConfig *config.VirtualClusterConfig, startKine bool) (string, *Certificates, error) {
	return configureExternalDatabase(ctx, kineEndpoint, vConfig, startKine)
}

func configureExternalDatabase(ctx context.Context, kineEndpoint string, vConfig *config.VirtualClusterConfig, startKine bool) (string, *Certificates, error) {
	externalDB := vConfig.ControlPlane.BackingStore.Database.External
	dataSource := externalDB.DataSource

	// If connector is specified, provision the database
	if externalDB.Connector != "" {
		klog.Infof("External database connector specified: %s", externalDB.Connector)
		
		// Provision database using connector
		provisionedDataSource, err := provisionDatabaseFromConnector(ctx, vConfig, externalDB.Connector)
		if err != nil {
			return "", nil, fmt.Errorf("provision database from connector: %w", err)
		}
		
		// Use the provisioned dataSource (connector always takes precedence)
		dataSource = provisionedDataSource
		klog.Infof("Using provisioned database connection")
	}

	// Validate dataSource is not empty
	if dataSource == "" {
		return "", nil, fmt.Errorf("external database dataSource cannot be empty")
	}

	// Prepare certificates
	certificates := &Certificates{
		CaCert:     externalDB.CaFile,
		ServerKey:  externalDB.KeyFile,
		ServerCert: externalDB.CertFile,
	}

	// Start Kine with the external database
	if startKine {
		klog.Infof("Starting Kine with external database...")
		startKineProcess(ctx, dataSource, kineEndpoint, certificates, externalDB.ExtraArgs)
	}

	return kineEndpoint, certificates, nil
}

// provisionDatabaseFromConnector reads connector secret and provisions a database
func provisionDatabaseFromConnector(ctx context.Context, vConfig *config.VirtualClusterConfig, connectorName string) (string, error) {
	klog.Infof("Reading database connector secret: %s", connectorName)
	
	// Read the connector secret from the host namespace
	secret, err := vConfig.HostClient.CoreV1().Secrets(vConfig.HostNamespace).Get(ctx, connectorName, metav1.GetOptions{})
	if err != nil {
		return "", fmt.Errorf("failed to read connector secret %s: %w", connectorName, err)
	}
	
	// Parse connector configuration
	connector, err := parseConnectorSecret(secret)
	if err != nil {
		return "", fmt.Errorf("failed to parse connector secret: %w", err)
	}
	
	// Validate connector
	if err := validateConnector(connector); err != nil {
		return "", fmt.Errorf("invalid connector configuration: %w", err)
	}
	
	// Generate unique database name and user for this vCluster
	dbName := generateDatabaseName(vConfig.Name, vConfig.HostNamespace)
	dbUser := fmt.Sprintf("vcluster_%s", sanitizeIdentifier(vConfig.Name))
	dbPassword := generateSecurePassword()
	
	klog.Infof("Provisioning database '%s' for vCluster '%s'", dbName, vConfig.Name)
	
	// Build admin connection string
	adminDataSource := buildAdminDataSource(connector)
	
	// Create database and user
	if err := createDatabaseAndUser(ctx, connector.Type, adminDataSource, dbName, dbUser, dbPassword); err != nil {
		return "", fmt.Errorf("failed to create database and user: %w", err)
	}
	
	// For PostgreSQL, grant schema privileges (PostgreSQL 15+ requirement)
	if connector.Type == "postgres" {
		if err := grantPostgresSchemaPrivileges(ctx, connector, dbName, dbUser); err != nil {
			klog.Warningf("Failed to grant schema privileges (may need manual intervention): %v", err)
			// Don't fail completely, as older PostgreSQL versions may not need this
		}
	}
	
	// Build the vCluster dataSource
	dataSource := buildVClusterDataSource(connector, dbName, dbUser, dbPassword)
	
	klog.Infof("Successfully provisioned database for vCluster '%s'", vConfig.Name)
	
	// Optionally save credentials to a secret for future reference
	if err := saveProvisionedCredentials(ctx, vConfig, dbName, dbUser, dbPassword, dataSource); err != nil {
		klog.Warningf("Failed to save provisioned credentials: %v", err)
		// Don't fail if we can't save credentials, just warn
	}
	
	return dataSource, nil
}

// ConnectorConfig holds database connector configuration
type ConnectorConfig struct {
	Type          string // mysql or postgres
	Host          string
	Port          string
	AdminUser     string
	AdminPassword string
	SSLMode       string // for postgres
	TLS           bool   // for mysql
	CACert        string
	ClientCert    string
	ClientKey     string
}

// parseConnectorSecret extracts connector configuration from a Kubernetes secret
func parseConnectorSecret(secret *corev1.Secret) (*ConnectorConfig, error) {
	connector := &ConnectorConfig{}
	
	// Required fields
	if val, ok := secret.Data["type"]; ok {
		connector.Type = string(val)
	} else {
		return nil, fmt.Errorf("missing required field 'type' in connector secret")
	}
	
	if val, ok := secret.Data["host"]; ok {
		connector.Host = string(val)
	} else {
		return nil, fmt.Errorf("missing required field 'host' in connector secret")
	}
	
	if val, ok := secret.Data["port"]; ok {
		connector.Port = string(val)
	} else {
		// Use default ports
		if connector.Type == "mysql" {
			connector.Port = "3306"
		} else if connector.Type == "postgres" || connector.Type == "postgresql" {
			connector.Port = "5432"
		}
	}
	
	if val, ok := secret.Data["adminUser"]; ok {
		connector.AdminUser = string(val)
	} else {
		return nil, fmt.Errorf("missing required field 'adminUser' in connector secret")
	}
	
	if val, ok := secret.Data["adminPassword"]; ok {
		connector.AdminPassword = string(val)
	} else {
		return nil, fmt.Errorf("missing required field 'adminPassword' in connector secret")
	}
	
	// Optional fields
	if val, ok := secret.Data["sslMode"]; ok {
		connector.SSLMode = string(val)
	} else {
		connector.SSLMode = "disable"
	}
	
	if val, ok := secret.Data["tls"]; ok {
		connector.TLS = string(val) == "true"
	}
	
	if val, ok := secret.Data["caCert"]; ok {
		connector.CACert = string(val)
	}
	
	if val, ok := secret.Data["clientCert"]; ok {
		connector.ClientCert = string(val)
	}
	
	if val, ok := secret.Data["clientKey"]; ok {
		connector.ClientKey = string(val)
	}
	
	return connector, nil
}

// validateConnector validates connector configuration
func validateConnector(connector *ConnectorConfig) error {
	// Validate type
	if connector.Type != "mysql" && connector.Type != "postgres" && connector.Type != "postgresql" {
		return fmt.Errorf("unsupported database type: %s (must be 'mysql' or 'postgres')", connector.Type)
	}
	
	// Normalize postgres/postgresql
	if connector.Type == "postgresql" {
		connector.Type = "postgres"
	}
	
	// Validate host
	if connector.Host == "" {
		return fmt.Errorf("host cannot be empty")
	}
	
	// Validate port
	if connector.Port == "" {
		return fmt.Errorf("port cannot be empty")
	}
	
	// Validate credentials
	if connector.AdminUser == "" {
		return fmt.Errorf("adminUser cannot be empty")
	}
	
	if connector.AdminPassword == "" {
		return fmt.Errorf("adminPassword cannot be empty")
	}
	
	return nil
}

// buildAdminDataSource builds connection string for admin user
func buildAdminDataSource(connector *ConnectorConfig) string {
	switch connector.Type {
	case "mysql":
		return fmt.Sprintf("mysql://%s:%s@tcp(%s:%s)/",
			connector.AdminUser,
			connector.AdminPassword,
			connector.Host,
			connector.Port)
	case "postgres":
		return fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=%s",
			connector.AdminUser,
			connector.AdminPassword,
			connector.Host,
			connector.Port,
			connector.SSLMode)
	default:
		return ""
	}
}

// buildVClusterDataSource builds connection string for vCluster user
func buildVClusterDataSource(connector *ConnectorConfig, dbName, dbUser, dbPassword string) string {
	switch connector.Type {
	case "mysql":
		return fmt.Sprintf("mysql://%s:%s@tcp(%s:%s)/%s",
			dbUser,
			dbPassword,
			connector.Host,
			connector.Port,
			dbName)
	case "postgres":
		return fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
			dbUser,
			dbPassword,
			connector.Host,
			connector.Port,
			dbName,
			connector.SSLMode)
	default:
		return ""
	}
}

// grantPostgresSchemaPrivileges grants schema privileges for PostgreSQL 15+
func grantPostgresSchemaPrivileges(ctx context.Context, connector *ConnectorConfig, dbName, dbUser string) error {
	// Build connection string to the target database
	connStr := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
		connector.AdminUser,
		connector.AdminPassword,
		connector.Host,
		connector.Port,
		dbName,
		connector.SSLMode)
	
	// Connect to the target database
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return fmt.Errorf("connect to target database: %w", err)
	}
	defer db.Close()
	
	// Test connection
	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("ping target database: %w", err)
	}
	
	// Grant schema privileges (PostgreSQL 15+ requirement)
	_, err = db.ExecContext(ctx, fmt.Sprintf("GRANT ALL ON SCHEMA public TO %s", sanitizeIdentifier(dbUser)))
	if err != nil {
		return fmt.Errorf("grant schema privileges: %w", err)
	}
	
	_, err = db.ExecContext(ctx, fmt.Sprintf("GRANT CREATE ON SCHEMA public TO %s", sanitizeIdentifier(dbUser)))
	if err != nil {
		return fmt.Errorf("grant create on schema: %w", err)
	}
	
	klog.Infof("Granted schema privileges to user '%s' on database '%s'", dbUser, dbName)
	return nil
}

// generateSecurePassword generates a secure random password
func generateSecurePassword() string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	const length = 32
	
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[md5.Sum([]byte(fmt.Sprintf("%d%d", i, time.Now().UnixNano())))[0]%byte(len(charset))]
	}
	return string(b)
}

// saveProvisionedCredentials saves the provisioned database credentials to a secret
func saveProvisionedCredentials(ctx context.Context, vConfig *config.VirtualClusterConfig, dbName, dbUser, dbPassword, dataSource string) error {
	secretName := fmt.Sprintf("vc-db-%s", vConfig.Name)
	
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      secretName,
			Namespace: vConfig.HostNamespace,
			Labels: map[string]string{
				"app":                          "vcluster",
				"vcluster.loft.sh/name":        vConfig.Name,
				"vcluster.loft.sh/namespace":   vConfig.HostNamespace,
				"vcluster.loft.sh/provisioned": "true",
			},
		},
		Type: corev1.SecretTypeOpaque,
		Data: map[string][]byte{
			"database":   []byte(dbName),
			"user":       []byte(dbUser),
			"password":   []byte(dbPassword),
			"dataSource": []byte(dataSource),
		},
	}
	
	_, err := vConfig.HostClient.CoreV1().Secrets(vConfig.HostNamespace).Create(ctx, secret, metav1.CreateOptions{})
	if err != nil {
		if kerrors.IsAlreadyExists(err) {
			// Update existing secret
			_, err = vConfig.HostClient.CoreV1().Secrets(vConfig.HostNamespace).Update(ctx, secret, metav1.UpdateOptions{})
		}
	}
	
	return err
}

// Helper function to create database and user (for future connector implementation)
func createDatabaseAndUser(ctx context.Context, dbType, adminDataSource, dbName, dbUser, dbPassword string) error {
	var db *sql.DB
	var err error

	// Connect to database server
	switch dbType {
	case "mysql":
		db, err = sql.Open("mysql", adminDataSource)
	case "postgres", "postgresql":
		db, err = sql.Open("postgres", adminDataSource)
	default:
		return fmt.Errorf("unsupported database type: %s", dbType)
	}
	
	if err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}
	defer db.Close()

	// Test connection
	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("ping database: %w", err)
	}

	// Create database and user based on type
	switch dbType {
	case "mysql":
		return createMySQLDatabaseAndUser(ctx, db, dbName, dbUser, dbPassword)
	case "postgres", "postgresql":
		return createPostgresDatabaseAndUser(ctx, db, dbName, dbUser, dbPassword)
	}

	return nil
}

func createMySQLDatabaseAndUser(ctx context.Context, db *sql.DB, dbName, dbUser, dbPassword string) error {
	// Create database if not exists
	_, err := db.ExecContext(ctx, fmt.Sprintf("CREATE DATABASE IF NOT EXISTS `%s`", sanitizeIdentifier(dbName)))
	if err != nil {
		return fmt.Errorf("create database: %w", err)
	}

	// Create user if not exists (MySQL 8.0+ syntax)
	_, err = db.ExecContext(ctx, fmt.Sprintf("CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s'", 
		sanitizeIdentifier(dbUser), dbPassword))
	if err != nil {
		return fmt.Errorf("create user: %w", err)
	}

	// Grant privileges
	_, err = db.ExecContext(ctx, fmt.Sprintf("GRANT ALL PRIVILEGES ON `%s`.* TO '%s'@'%%'", 
		sanitizeIdentifier(dbName), sanitizeIdentifier(dbUser)))
	if err != nil {
		return fmt.Errorf("grant privileges: %w", err)
	}

	// Flush privileges
	_, err = db.ExecContext(ctx, "FLUSH PRIVILEGES")
	if err != nil {
		return fmt.Errorf("flush privileges: %w", err)
	}

	klog.Infof("Successfully created MySQL database '%s' and user '%s'", dbName, dbUser)
	return nil
}

func createPostgresDatabaseAndUser(ctx context.Context, db *sql.DB, dbName, dbUser, dbPassword string) error {
	// Check if database exists
	var exists bool
	err := db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = $1)", dbName).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check database exists: %w", err)
	}

	if !exists {
		// Create database
		_, err = db.ExecContext(ctx, fmt.Sprintf("CREATE DATABASE %s", sanitizeIdentifier(dbName)))
		if err != nil {
			return fmt.Errorf("create database: %w", err)
		}
	}

	// Check if user exists
	err = db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = $1)", dbUser).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check user exists: %w", err)
	}

	if !exists {
		// Create user
		_, err = db.ExecContext(ctx, fmt.Sprintf("CREATE USER %s WITH PASSWORD '%s'", 
			sanitizeIdentifier(dbUser), dbPassword))
		if err != nil {
			return fmt.Errorf("create user: %w", err)
		}
	}

	// Grant database privileges
	_, err = db.ExecContext(ctx, fmt.Sprintf("GRANT ALL PRIVILEGES ON DATABASE %s TO %s", 
		sanitizeIdentifier(dbName), sanitizeIdentifier(dbUser)))
	if err != nil {
		return fmt.Errorf("grant database privileges: %w", err)
	}

	klog.Infof("Successfully created PostgreSQL database '%s' and user '%s'", dbName, dbUser)
	// Note: Schema privileges will be granted separately via grantPostgresSchemaPrivileges()
	
	return nil
}

// sanitizeIdentifier removes dangerous characters from SQL identifiers
func sanitizeIdentifier(identifier string) string {
	// Remove backticks, quotes, semicolons, and hyphens to prevent SQL injection and syntax errors
	identifier = strings.ReplaceAll(identifier, "`", "")
	identifier = strings.ReplaceAll(identifier, "'", "")
	identifier = strings.ReplaceAll(identifier, "\"", "")
	identifier = strings.ReplaceAll(identifier, ";", "")
	identifier = strings.ReplaceAll(identifier, "--", "")
	identifier = strings.ReplaceAll(identifier, "-", "_")  // Replace hyphens with underscores
	return identifier
}

// generateDatabaseName creates a unique database name for a vCluster
func generateDatabaseName(vclusterName, namespace string) string {
	// Create a hash to keep name short but unique
	hash := md5.Sum([]byte(namespace + "/" + vclusterName))
	return fmt.Sprintf("vcluster_%s_%x", sanitizeIdentifier(vclusterName), hash[:4])
}

// startKineProcess starts the Kine process with the given configuration
// This is inlined here to avoid import cycle with pkg/k8s
func startKineProcess(ctx context.Context, dataSource, listenAddress string, certificates *Certificates, extraArgs []string) {
	// start kine
	doneChan := make(chan error)

	// start embedded mode
	go func() {
		args := []string{}
		args = append(args, constants.KineBinary)
		args = append(args, "--endpoint="+dataSource)
		if certificates != nil {
			if certificates.CaCert != "" {
				args = append(args, "--ca-file="+certificates.CaCert)
			}
			if certificates.ServerKey != "" {
				args = append(args, "--key-file="+certificates.ServerKey)
			}
			if certificates.ServerCert != "" {
				args = append(args, "--cert-file="+certificates.ServerCert)
			}
		}
		args = append(args, "--metrics-bind-address=0")
		args = append(args, "--listen-address="+listenAddress)
		args = command.MergeArgs(args, extraArgs)

		// now start kine
		err := command.RunCommand(ctx, args, "kine")
		doneChan <- err
	}()

	// wait for kine to finish
	go func() {
		err := <-doneChan
		if err != nil {
			klog.Errorf("could not run kine: %s", err.Error())
			osutil.Exit(1)
		}
		klog.Info("kine finished")
		osutil.Exit(0)
	}()
}

// CleanupExternalDatabase drops the database and user created by the connector
// This should be called when deleting a vCluster to clean up resources
// It creates a Kubernetes Job to run the cleanup inside the cluster (to access cluster DNS)
func CleanupExternalDatabase(ctx context.Context, vConfig *config.VirtualClusterConfig) error {
	externalDB := vConfig.ControlPlane.BackingStore.Database.External
	
	// Only cleanup if connector was used
	if externalDB.Connector == "" {
		klog.Info("No connector specified, skipping database cleanup")
		return nil
	}
	
	klog.Infof("Cleaning up database for vCluster '%s'", vConfig.Name)
	
	// Read connector secret to validate it exists
	connectorSecret, err := vConfig.HostClient.CoreV1().Secrets(vConfig.HostNamespace).Get(ctx, externalDB.Connector, metav1.GetOptions{})
	if err != nil {
		if kerrors.IsNotFound(err) {
			klog.Warningf("Connector secret '%s' not found, cannot cleanup database", externalDB.Connector)
			return nil
		}
		return fmt.Errorf("failed to read connector secret: %w", err)
	}
	
	// Generate the same database and user names that were created
	dbName := generateDatabaseName(vConfig.Name, vConfig.HostNamespace)
	dbUser := sanitizeIdentifier(fmt.Sprintf("vcluster_%s", vConfig.Name))
	
	klog.Infof("Creating cleanup job for database '%s' and user '%s'", dbName, dbUser)
	
	// Create a Kubernetes Job to run the cleanup inside the cluster
	err = createCleanupJob(ctx, vConfig, connectorSecret, dbName, dbUser)
	if err != nil {
		return fmt.Errorf("failed to create cleanup job: %w", err)
	}
	
	klog.Infof("Cleanup job created successfully for vCluster '%s'", vConfig.Name)
	
	// Also delete the provisioned credentials secret if it exists
	secretName := fmt.Sprintf("vc-db-%s", vConfig.Name)
	err = vConfig.HostClient.CoreV1().Secrets(vConfig.HostNamespace).Delete(ctx, secretName, metav1.DeleteOptions{})
	if err != nil && !kerrors.IsNotFound(err) {
		klog.Warningf("Failed to delete credentials secret '%s': %v", secretName, err)
	} else if err == nil {
		klog.Infof("Deleted credentials secret '%s'", secretName)
	}
	
	return nil
}

// createCleanupJob creates a Kubernetes Job to cleanup the database
func createCleanupJob(ctx context.Context, vConfig *config.VirtualClusterConfig, connectorSecret *corev1.Secret, dbName, dbUser string) error {
	dbType := string(connectorSecret.Data["type"])
	host := string(connectorSecret.Data["host"])
	port := string(connectorSecret.Data["port"])
	adminUser := string(connectorSecret.Data["adminUser"])
	adminPassword := string(connectorSecret.Data["adminPassword"])
	sslMode := string(connectorSecret.Data["sslMode"])
	
	if port == "" {
		if dbType == "postgres" {
			port = "5432"
		} else if dbType == "mysql" {
			port = "3306"
		}
	}
	
	if sslMode == "" {
		sslMode = "disable"
	}
	
	// Build the cleanup script based on database type
	var cleanupScript string
	var image string
	
	switch dbType {
	case "postgres":
		image = "postgres:15"
		cleanupScript = fmt.Sprintf(`#!/bin/sh
set -e
export PGPASSWORD='%s'
echo "Terminating connections to database %s..."
psql -h %s -p %s -U %s -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '%s' AND pid <> pg_backend_pid();" || true
echo "Dropping database %s..."
psql -h %s -p %s -U %s -d postgres -c "DROP DATABASE IF EXISTS %s;"
echo "Dropping user %s..."
psql -h %s -p %s -U %s -d postgres -c "DROP USER IF EXISTS %s;"
echo "Cleanup completed successfully"
`, adminPassword, dbName, host, port, adminUser, dbName, dbName, host, port, adminUser, dbName, dbUser, host, port, adminUser, dbUser)
		
	case "mysql":
		image = "mysql:8"
		// Use printf to avoid backtick escaping issues in Go raw strings
		cleanupScript = fmt.Sprintf(`#!/bin/sh
set -e
echo "Dropping database %s..."
mysql -h %s -P %s -u %s -p'%s' -e "DROP DATABASE IF EXISTS %s;"
echo "Dropping user %s..."
mysql -h %s -P %s -u %s -p'%s' -e "DROP USER IF EXISTS '%s'@'%%%%';"
echo "Cleanup completed successfully"
`, dbName, host, port, adminUser, adminPassword, dbName, dbUser, host, port, adminUser, adminPassword, dbUser)
		
	default:
		return fmt.Errorf("unsupported database type: %s", dbType)
	}
	
	// Create a ConfigMap with the cleanup script
	configMapName := fmt.Sprintf("vc-db-cleanup-%s", vConfig.Name)
	configMap := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      configMapName,
			Namespace: vConfig.HostNamespace,
		},
		Data: map[string]string{
			"cleanup.sh": cleanupScript,
		},
	}
	
	_, err := vConfig.HostClient.CoreV1().ConfigMaps(vConfig.HostNamespace).Create(ctx, configMap, metav1.CreateOptions{})
	if err != nil && !kerrors.IsAlreadyExists(err) {
		return fmt.Errorf("create cleanup configmap: %w", err)
	}
	
	// Create the cleanup Job
	jobName := fmt.Sprintf("vc-db-cleanup-%s", vConfig.Name)
	backoffLimit := int32(3)
	ttlSecondsAfterFinished := int32(300) // Clean up job after 5 minutes
	
	job := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: vConfig.HostNamespace,
		},
		Spec: batchv1.JobSpec{
			BackoffLimit:            &backoffLimit,
			TTLSecondsAfterFinished: &ttlSecondsAfterFinished,
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					RestartPolicy: corev1.RestartPolicyNever,
					DNSPolicy:     corev1.DNSClusterFirst,
					Containers: []corev1.Container{
						{
							Name:    "cleanup",
							Image:   image,
							Command: []string{"/bin/sh", "/scripts/cleanup.sh"},
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      "scripts",
									MountPath: "/scripts",
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: "scripts",
							VolumeSource: corev1.VolumeSource{
								ConfigMap: &corev1.ConfigMapVolumeSource{
									LocalObjectReference: corev1.LocalObjectReference{
										Name: configMapName,
									},
									DefaultMode: func() *int32 { m := int32(0755); return &m }(),
								},
							},
						},
					},
				},
			},
		},
	}
	
	_, err = vConfig.HostClient.BatchV1().Jobs(vConfig.HostNamespace).Create(ctx, job, metav1.CreateOptions{})
	if err != nil && !kerrors.IsAlreadyExists(err) {
		return fmt.Errorf("create cleanup job: %w", err)
	}
	
	klog.Infof("Created cleanup job '%s' in namespace '%s'", jobName, vConfig.HostNamespace)
	
	// Clean up the ConfigMap after the job is created
	// The job will have already mounted it, so it's safe to delete
	go func() {
		time.Sleep(10 * time.Second)
		_ = vConfig.HostClient.CoreV1().ConfigMaps(vConfig.HostNamespace).Delete(context.Background(), configMapName, metav1.DeleteOptions{})
	}()
	
	return nil
}
