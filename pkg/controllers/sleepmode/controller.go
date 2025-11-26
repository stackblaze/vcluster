package sleepmode

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/loft-sh/log"
	"github.com/loft-sh/vcluster/pkg/config"
	"github.com/loft-sh/vcluster/pkg/constants"
	"github.com/loft-sh/vcluster/pkg/lifecycle"
	"github.com/loft-sh/vcluster/pkg/util/loghelper"
	appsv1 "k8s.io/api/apps/v1"
	kerrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/client-go/kubernetes"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

const (
	// RequeueInterval is how often to check for sleep conditions
	RequeueInterval = 1 * time.Minute
)

type SleepModeReconciler struct {
	client.Client
	KubeClient kubernetes.Interface
	Config     *config.VirtualClusterConfig
	Log        loghelper.Logger
	Logger     log.BaseLogger
}

func (r *SleepModeReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	// Get the StatefulSet or Deployment
	var obj client.Object
	var objType string

	// Try StatefulSet first
	sts := &appsv1.StatefulSet{}
	err := r.Client.Get(ctx, req.NamespacedName, sts)
	if err == nil {
		obj = sts
		objType = "StatefulSet"
	} else if !kerrors.IsNotFound(err) {
		return ctrl.Result{RequeueAfter: RequeueInterval}, err
	} else {
		// Try Deployment
		deploy := &appsv1.Deployment{}
		err = r.Client.Get(ctx, req.NamespacedName, deploy)
		if err != nil {
			if kerrors.IsNotFound(err) {
				// Object doesn't exist, nothing to do
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: RequeueInterval}, err
		}
		obj = deploy
		objType = "Deployment"
	}

	// Check if this is a vCluster resource
	if !isVClusterResource(obj) {
		return ctrl.Result{}, nil
	}

	// Check if already paused
	if lifecycle.IsPaused(obj) {
		r.Log.Debugf("vCluster %s/%s is already paused, skipping", req.Namespace, req.Name)
		return ctrl.Result{RequeueAfter: RequeueInterval}, nil
	}

	// Check if sleep mode is enabled
	if r.Config.SleepMode == nil || !r.Config.SleepMode.Enabled {
		return ctrl.Result{}, nil
	}

	// Check if afterInactivity is configured
	if r.Config.SleepMode.AutoSleep.AfterInactivity == "" {
		return ctrl.Result{RequeueAfter: RequeueInterval}, nil
	}

	// Parse inactivity duration
	inactivityDuration, err := time.ParseDuration(string(r.Config.SleepMode.AutoSleep.AfterInactivity))
	if err != nil {
		r.Log.Errorf("Invalid afterInactivity duration: %v", err)
		return ctrl.Result{RequeueAfter: RequeueInterval}, nil
	}

	// Get last activity timestamp
	lastActivityStr := obj.GetAnnotations()[constants.SleepModeLastActivityAnnotation]
	if lastActivityStr == "" {
		// No activity recorded yet, set current time as baseline
		r.Log.Debugf("No activity recorded for vCluster %s/%s, setting baseline", req.Namespace, req.Name)
		return r.updateActivityAnnotation(ctx, obj, objType, req.Namespace, req.Name)
	}

	lastActivity, err := strconv.ParseInt(lastActivityStr, 10, 64)
	if err != nil {
		r.Log.Errorf("Invalid last activity timestamp for vCluster %s/%s: %v", req.Namespace, req.Name, err)
		return r.updateActivityAnnotation(ctx, obj, objType, req.Namespace, req.Name)
	}

	// Calculate inactivity duration
	lastActivityTime := time.Unix(lastActivity, 0)
	inactivityTime := time.Since(lastActivityTime)

	// Check if inactivity threshold exceeded
	if inactivityTime >= inactivityDuration {
		r.Log.Infof("vCluster %s/%s has been inactive for %v (threshold: %v), putting to sleep", req.Namespace, req.Name, inactivityTime, inactivityDuration)

		// Extract vCluster name from labels
		vClusterName := extractVClusterName(obj)
		if vClusterName == "" {
			vClusterName = req.Name
		}

		// Convert kubernetes.Interface to *kubernetes.Clientset for lifecycle functions
		clientset, ok := r.KubeClient.(*kubernetes.Clientset)
		if !ok {
			r.Log.Errorf("Failed to convert kubernetes.Interface to Clientset for vCluster %s/%s", req.Namespace, req.Name)
			return ctrl.Result{RequeueAfter: RequeueInterval}, fmt.Errorf("invalid kubernetes client type")
		}

		// Pause the vCluster
		err = lifecycle.PauseVCluster(ctx, clientset, vClusterName, req.Namespace, false, r.Logger)
		if err != nil {
			r.Log.Errorf("Failed to pause vCluster %s/%s: %v", req.Namespace, req.Name, err)
			return ctrl.Result{RequeueAfter: RequeueInterval}, err
		}

		// Delete workload pods
		labelSelector := "vcluster.loft.sh/managed-by=" + vClusterName
		err = lifecycle.DeletePods(ctx, clientset, labelSelector, req.Namespace)
		if err != nil {
			r.Log.Errorf("Failed to delete pods for vCluster %s/%s: %v", req.Namespace, req.Name, err)
			// Continue anyway, pause was successful
		}

		// Delete multi-namespace workloads if applicable
		err = lifecycle.DeleteMultiNamespaceVClusterWorkloads(ctx, clientset, vClusterName, req.Namespace, r.Logger)
		if err != nil {
			r.Log.Errorf("Failed to delete multi-namespace workloads for vCluster %s/%s: %v", req.Namespace, req.Name, err)
			// Continue anyway
		}

		r.Log.Infof("Successfully put vCluster %s/%s to sleep", req.Namespace, req.Name)
	}

	// Requeue to check again later
	return ctrl.Result{RequeueAfter: RequeueInterval}, nil
}

func (r *SleepModeReconciler) updateActivityAnnotation(ctx context.Context, obj client.Object, objType, namespace, name string) (ctrl.Result, error) {
	annotations := obj.GetAnnotations()
	if annotations == nil {
		annotations = make(map[string]string)
	}
	annotations[constants.SleepModeLastActivityAnnotation] = strconv.FormatInt(time.Now().Unix(), 10)
	obj.SetAnnotations(annotations)

	var err error
	switch objType {
	case "StatefulSet":
		err = r.Client.Update(ctx, obj.(*appsv1.StatefulSet))
	case "Deployment":
		err = r.Client.Update(ctx, obj.(*appsv1.Deployment))
	}

	if err != nil {
		return ctrl.Result{RequeueAfter: RequeueInterval}, fmt.Errorf("failed to update activity annotation: %w", err)
	}

	return ctrl.Result{RequeueAfter: RequeueInterval}, nil
}

func isVClusterResource(obj client.Object) bool {
	labels := obj.GetLabels()
	if labels == nil {
		return false
	}
	// Check for vCluster identifying labels
	return labels["app"] == "vcluster" || labels["app.kubernetes.io/name"] == "vcluster"
}

func extractVClusterName(obj client.Object) string {
	labels := obj.GetLabels()
	if labels == nil {
		return ""
	}
	// Try to get release name or vCluster name from labels
	if release, ok := labels["release"]; ok {
		return release
	}
	if name, ok := labels["app.kubernetes.io/instance"]; ok {
		return name
	}
	return ""
}

// SetupWithManager adds the controller to the manager
func (r *SleepModeReconciler) SetupWithManager(mgr ctrl.Manager) error {
	// Create predicate to only watch vCluster resources
	vClusterPredicate := predicate.NewPredicateFuncs(func(obj client.Object) bool {
		return isVClusterResource(obj)
	})

	// Handler to enqueue requests for Deployments
	deploymentHandler := handler.EnqueueRequestsFromMapFunc(func(_ context.Context, obj client.Object) []reconcile.Request {
		if !isVClusterResource(obj) {
			return nil
		}
		return []reconcile.Request{{
			NamespacedName: client.ObjectKeyFromObject(obj),
		}}
	})

	return ctrl.NewControllerManagedBy(mgr).
		WithOptions(controller.Options{
			CacheSyncTimeout: constants.DefaultCacheSyncTimeout,
		}).
		Named("sleepmode-controller").
		For(&appsv1.StatefulSet{}, builder.WithPredicates(vClusterPredicate)).
		Watches(&appsv1.Deployment{}, deploymentHandler, builder.WithPredicates(vClusterPredicate)).
		Complete(r)
}

