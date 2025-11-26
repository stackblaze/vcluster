package setup

import (
	"context"
	"sync"
	"time"

	vclusterconfig "github.com/loft-sh/vcluster/config"
	"github.com/loft-sh/vcluster/pkg/config"
	"github.com/loft-sh/vcluster/pkg/etcd"
	"github.com/loft-sh/vcluster/pkg/util/osutil"
	"k8s.io/klog/v2"
)

var (
	cleanupHandlerRegistered = false
	cleanupHandlerMu         sync.Mutex
)

// RegisterDatabaseCleanupHandler registers a cleanup handler that will be called
// when the vCluster receives a termination signal (SIGTERM/SIGINT).
// This allows the vCluster to clean up its own database before shutting down,
// using the same approach as database creation.
func RegisterDatabaseCleanupHandler(ctx context.Context, vConfig *config.VirtualClusterConfig) {
	// Only register if external database connector is used
	connectorName := vConfig.ControlPlane.BackingStore.Database.External.Connector
	if connectorName == "" {
		klog.Info("No external database connector, skipping cleanup handler registration")
		return
	}

	cleanupHandlerMu.Lock()
	defer cleanupHandlerMu.Unlock()

	if cleanupHandlerRegistered {
		klog.Warning("Cleanup handler already registered, skipping")
		return
	}

	// Store values needed for cleanup (don't capture vConfig pointer which might become invalid)
	vClusterName := vConfig.Name
	hostNamespace := vConfig.HostNamespace
	hostClient := vConfig.HostClient // This should remain valid
	
	// Store the connector config in the closure
	connectorConfig := vConfig.ControlPlane.BackingStore.Database.External

	klog.Infof("Registering database cleanup handler for vCluster '%s' with connector '%s'", 
		vClusterName, connectorName)

	osutil.RegisterInterruptHandler(func() {
		klog.Info("=== SHUTDOWN HANDLER TRIGGERED ===")
		klog.Infof("Shutdown signal received for vCluster '%s', cleaning up external database...", vClusterName)
		
		// Create a new context with timeout for cleanup (the original ctx might be cancelled)
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		
		// Reconstruct vConfig for cleanup (with stored values)
		cleanupVConfig := &config.VirtualClusterConfig{
			Name:          vClusterName,
			HostNamespace: hostNamespace,
			HostClient:    hostClient,
			Config: vclusterconfig.Config{
				ControlPlane: vclusterconfig.ControlPlane{
					BackingStore: vclusterconfig.BackingStore{
						Database: vclusterconfig.Database{
							External: connectorConfig,
						},
					},
				},
			},
		}
		
		klog.Infof("Calling CleanupExternalDatabase for vCluster '%s'", vClusterName)
		
		// Use the same cleanup logic
		err := etcd.CleanupExternalDatabase(cleanupCtx, cleanupVConfig)
		if err != nil {
			klog.Errorf("Failed to cleanup external database: %v", err)
			// Don't fail the shutdown, just log the error
		} else {
			klog.Info("Successfully cleaned up external database")
		}
		
		klog.Info("=== SHUTDOWN HANDLER COMPLETE ===")
	})
	
	cleanupHandlerRegistered = true
	klog.Info("Cleanup handler registered successfully")
}
