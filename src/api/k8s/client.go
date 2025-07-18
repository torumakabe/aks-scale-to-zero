package k8s

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

// ClientInterface defines the interface for Kubernetes client operations
type ClientInterface interface {
	GetClientset() kubernetes.Interface
	ScaleDeployment(ctx context.Context, namespace, name string, replicas int32) error
	GetDeploymentStatus(ctx context.Context, namespace, name string) (*DeploymentStatus, error)
}

// Client wraps the Kubernetes clientset
type Client struct {
	clientset kubernetes.Interface
}

// NewClient creates a new Kubernetes client
// It automatically detects if running inside a cluster (InClusterConfig)
// or outside (using kubeconfig file)
func NewClient() (*Client, error) {
	config, err := getConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to get kubernetes config: %w", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	return &Client{
		clientset: clientset,
	}, nil
}

// getConfig returns the appropriate Kubernetes configuration
func getConfig() (*rest.Config, error) {
	// Try in-cluster config first (when running inside a pod)
	config, err := rest.InClusterConfig()
	if err == nil {
		return config, nil
	}

	// Fall back to kubeconfig file (for local development)
	kubeconfigPath := os.Getenv("KUBECONFIG")
	if kubeconfigPath == "" {
		if home := homedir.HomeDir(); home != "" {
			kubeconfigPath = filepath.Join(home, ".kube", "config")
		}
	}

	config, err = clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	if err != nil {
		return nil, fmt.Errorf("failed to build config from kubeconfig: %w", err)
	}

	return config, nil
}

// GetClientset returns the underlying Kubernetes clientset
func (c *Client) GetClientset() kubernetes.Interface {
	return c.clientset
}

// ScaleDeployment scales a deployment to the specified number of replicas
func (c *Client) ScaleDeployment(ctx context.Context, namespace, name string, replicas int32) error {
	deploymentsClient := c.clientset.AppsV1().Deployments(namespace)

	// Get the deployment
	deployment, err := deploymentsClient.Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("failed to get deployment %s/%s: %w", namespace, name, err)
	}

	// Update the replica count
	deployment.Spec.Replicas = &replicas

	// Update the deployment
	_, err = deploymentsClient.Update(ctx, deployment, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to update deployment %s/%s: %w", namespace, name, err)
	}

	return nil
}

// GetDeploymentStatus retrieves the current status of a deployment
func (c *Client) GetDeploymentStatus(ctx context.Context, namespace, name string) (*DeploymentStatus, error) {
	deploymentsClient := c.clientset.AppsV1().Deployments(namespace)

	deployment, err := deploymentsClient.Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get deployment %s/%s: %w", namespace, name, err)
	}

	desiredReplicas := int32(0)
	if deployment.Spec.Replicas != nil {
		desiredReplicas = *deployment.Spec.Replicas
	}

	return &DeploymentStatus{
		Name:              deployment.Name,
		Namespace:         deployment.Namespace,
		DesiredReplicas:   desiredReplicas,
		CurrentReplicas:   deployment.Status.Replicas,
		AvailableReplicas: deployment.Status.AvailableReplicas,
		UpdatedReplicas:   deployment.Status.UpdatedReplicas,
		CreationTime:      deployment.CreationTimestamp.Time,
	}, nil
}

// DeploymentStatus represents the status of a deployment
type DeploymentStatus struct {
	Name              string
	Namespace         string
	DesiredReplicas   int32
	CurrentReplicas   int32
	AvailableReplicas int32
	UpdatedReplicas   int32
	CreationTime      time.Time
}
