package setup

import (
	"context"

	"github.com/loft-sh/vcluster/pkg/config"
	"github.com/loft-sh/vcluster/pkg/etcd"
	"github.com/loft-sh/vcluster/pkg/util/osutil"
	"k8s.io/klog/v2"
)

// RegisterDatabaseCleanupHandler registers a cleanup handler that will be called
// when the vCluster receives a termination signal (SIGTERM/SIGINT).
// This allows the vCluster to clean up its own database before shutting down,
// using the same approach as database creation.
func RegisterDatabaseCleanupHandler(ctx context.Context, vConfig *config.VirtualClusterConfig) {
	// Only register if external database connector is used
	if vConfig.ControlPlane.BackingStore.Database.External.Connector == "" {
		return
	}

	klog.Info("Registering database cleanup handler for shutdown")

	osutil.RegisterInterruptHandler(func() {
		klog.Info("Shutdown signal received, cleaning up external database...")
		
		// Use the same cleanup logic that was previously in the Job
		err := etcd.CleanupExternalDatabase(ctx, vConfig)
		if err != nil {
			klog.Errorf("Failed to cleanup external database: %v", err)
			// Don't fail the shutdown, just log the error
		} else {
			klog.Info("Successfully cleaned up external database")
		}
	})
}
