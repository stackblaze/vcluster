package sleepmode

import (
	"context"
	"strconv"
	"time"

	"github.com/loft-sh/vcluster/pkg/constants"
	kerrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/kubernetes"
)

// UpdateActivityAnnotation updates the last activity timestamp for a vCluster
// This should be called whenever an API request is made to the vCluster
func UpdateActivityAnnotation(ctx context.Context, kubeClient kubernetes.Interface, namespace string) error {
	// Find vCluster StatefulSet or Deployment in the namespace
	labelSelector := labels.Set{
		"app": "vcluster",
	}.AsSelector().String()

	// Try StatefulSet first
	stsList, err := kubeClient.AppsV1().StatefulSets(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err != nil {
		return err
	}

	if len(stsList.Items) > 0 {
		for i := range stsList.Items {
			sts := &stsList.Items[i]
			if isVClusterResource(sts) {
				return updateResourceActivity(ctx, kubeClient, namespace, sts.Name, "StatefulSet")
			}
		}
	}

	// Try Deployment
	deployList, err := kubeClient.AppsV1().Deployments(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err != nil {
		return err
	}

	if len(deployList.Items) > 0 {
		for i := range deployList.Items {
			deploy := &deployList.Items[i]
			if isVClusterResource(deploy) {
				return updateResourceActivity(ctx, kubeClient, namespace, deploy.Name, "Deployment")
			}
		}
	}

	return nil
}

func updateResourceActivity(ctx context.Context, kubeClient kubernetes.Interface, namespace, name, resourceType string) error {
	now := strconv.FormatInt(time.Now().Unix(), 10)

	switch resourceType {
	case "StatefulSet":
		sts, err := kubeClient.AppsV1().StatefulSets(namespace).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			if kerrors.IsNotFound(err) {
				return nil
			}
			return err
		}

		// Check if annotation already exists and is recent (within last minute)
		// to avoid excessive updates
		if lastActivity, ok := sts.Annotations[constants.SleepModeLastActivityAnnotation]; ok {
			if lastActivityInt, err := strconv.ParseInt(lastActivity, 10, 64); err == nil {
				lastActivityTime := time.Unix(lastActivityInt, 0)
				if time.Since(lastActivityTime) < time.Minute {
					// Already updated recently, skip
					return nil
				}
			}
		}

		// Update annotation
		if sts.Annotations == nil {
			sts.Annotations = make(map[string]string)
		}
		sts.Annotations[constants.SleepModeLastActivityAnnotation] = now

		_, err = kubeClient.AppsV1().StatefulSets(namespace).Update(ctx, sts, metav1.UpdateOptions{})
		return err

	case "Deployment":
		deploy, err := kubeClient.AppsV1().Deployments(namespace).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			if kerrors.IsNotFound(err) {
				return nil
			}
			return err
		}

		// Check if annotation already exists and is recent (within last minute)
		if lastActivity, ok := deploy.Annotations[constants.SleepModeLastActivityAnnotation]; ok {
			if lastActivityInt, err := strconv.ParseInt(lastActivity, 10, 64); err == nil {
				lastActivityTime := time.Unix(lastActivityInt, 0)
				if time.Since(lastActivityTime) < time.Minute {
					// Already updated recently, skip
					return nil
				}
			}
		}

		// Update annotation
		if deploy.Annotations == nil {
			deploy.Annotations = make(map[string]string)
		}
		deploy.Annotations[constants.SleepModeLastActivityAnnotation] = now

		_, err = kubeClient.AppsV1().Deployments(namespace).Update(ctx, deploy, metav1.UpdateOptions{})
		return err
	}

	return nil
}

