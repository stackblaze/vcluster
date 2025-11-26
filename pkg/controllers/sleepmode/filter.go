package sleepmode

import (
	"net/http"

	"github.com/loft-sh/vcluster/pkg/syncer/synccontext"
)

// WithActivityTracking adds activity tracking to API requests
func WithActivityTracking(handler http.Handler, ctx *synccontext.ControllerContext) http.Handler {
	// Only enable if sleep mode is enabled
	if ctx.Config.SleepMode == nil || !ctx.Config.SleepMode.Enabled {
		return handler
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Process the request first
		handler.ServeHTTP(w, r)

		// Update activity annotation asynchronously (don't block response)
		go func() {
			// Only track successful API requests (2xx status codes)
			// Note: We can't easily check status code here, so we'll update for all requests
			// The controller will handle the actual sleep logic
			_ = UpdateActivityAnnotation(r.Context(), ctx.Config.HostClient, ctx.Config.HostNamespace)
		}()
	})
}

