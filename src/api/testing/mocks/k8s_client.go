package mocks

import (
	"context"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/torumakabe/aks-scale-to-zero/api/k8s"
	"k8s.io/client-go/kubernetes"
)

// MockK8sClient is a mock implementation of the k8s.ClientInterface
type MockK8sClient struct {
	mock.Mock
}

// NewMockK8sClient creates a new mock k8s client
func NewMockK8sClient() *MockK8sClient {
	return &MockK8sClient{}
}

// Ensure MockK8sClient implements k8s.ClientInterface
var _ k8s.ClientInterface = (*MockK8sClient)(nil)

// GetClientset returns the underlying Kubernetes clientset
func (m *MockK8sClient) GetClientset() kubernetes.Interface {
	args := m.Called()
	if args.Get(0) != nil {
		return args.Get(0).(kubernetes.Interface)
	}
	return nil
}

// ScaleDeployment scales a deployment to the specified number of replicas
func (m *MockK8sClient) ScaleDeployment(ctx context.Context, namespace, name string, replicas int32) error {
	args := m.Called(ctx, namespace, name, replicas)
	return args.Error(0)
}

// GetDeploymentStatus retrieves the current status of a deployment
func (m *MockK8sClient) GetDeploymentStatus(ctx context.Context, namespace, name string) (*k8s.DeploymentStatus, error) {
	args := m.Called(ctx, namespace, name)
	if args.Get(0) != nil {
		return args.Get(0).(*k8s.DeploymentStatus), args.Error(1)
	}
	return nil, args.Error(1)
}

// MockDeploymentStatus creates a mock deployment status for testing
func MockDeploymentStatus(name, namespace string, current, desired int32) *k8s.DeploymentStatus {
	return &k8s.DeploymentStatus{
		Name:              name,
		Namespace:         namespace,
		DesiredReplicas:   desired,
		CurrentReplicas:   current,
		AvailableReplicas: current,
		UpdatedReplicas:   current,
		CreationTime:      time.Now().Add(-1 * time.Hour),
	}
}
