package handlers

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/torumakabe/aks-scale-to-zero/api/k8s"
	"github.com/torumakabe/aks-scale-to-zero/api/models"
	"github.com/torumakabe/aks-scale-to-zero/api/testing/helpers"
	"github.com/torumakabe/aks-scale-to-zero/api/testing/mocks"
	k8serrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestScaleToZero_Success(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-to-zero", handler.ScaleToZero)

	// Mock expectations
	status := &k8s.DeploymentStatus{
		Name:              "test-app",
		Namespace:         "test-ns",
		DesiredReplicas:   3,
		CurrentReplicas:   3,
		AvailableReplicas: 3,
		UpdatedReplicas:   3,
		CreationTime:      time.Now(),
	}
	mockClient.On("GetDeploymentStatus", mock.Anything, "test-ns", "test-app").Return(status, nil)
	mockClient.On("ScaleDeployment", mock.Anything, "test-ns", "test-app", int32(0)).Return(nil)

	// Test
	body := models.ScaleRequest{
		Reason: "Cost optimization",
	}
	w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/test-app/scale-to-zero", body)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)

	var response models.ScaleResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "success", response.Status)
	assert.Equal(t, "Deployment scaled to zero", response.Message)
	assert.NotNil(t, response.Deployment)
	assert.Equal(t, "test-ns", response.Deployment.Namespace)
	assert.Equal(t, int32(3), response.Deployment.PreviousReplicas)

	mockClient.AssertExpectations(t)
}

func TestScaleToZero_AlreadyScaledToZero(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-to-zero", handler.ScaleToZero)

	// Mock expectations
	status := &k8s.DeploymentStatus{
		Name:              "test-app",
		Namespace:         "test-ns",
		DesiredReplicas:   0,
		CurrentReplicas:   0,
		AvailableReplicas: 0,
		UpdatedReplicas:   0,
		CreationTime:      time.Now(),
	}
	mockClient.On("GetDeploymentStatus", mock.Anything, "test-ns", "test-app").Return(status, nil)
	mockClient.On("ScaleDeployment", mock.Anything, "test-ns", "test-app", int32(0)).Return(nil)

	// Test
	body := models.ScaleRequest{
		Reason: "Already scaled",
	}
	w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/test-app/scale-to-zero", body)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)

	var response models.ScaleResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "success", response.Status)
	assert.Equal(t, "Deployment scaled to zero", response.Message)

	mockClient.AssertExpectations(t)
}

func TestScaleToZero_DeploymentNotFound(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-to-zero", handler.ScaleToZero)

	// Mock expectations
	notFoundErr := &k8serrors.StatusError{
		ErrStatus: metav1.Status{
			Reason: metav1.StatusReasonNotFound,
			Code:   http.StatusNotFound,
		},
	}
	mockClient.On("GetDeploymentStatus", mock.Anything, "test-ns", "nonexistent").Return(nil, notFoundErr)

	// Test
	body := models.ScaleRequest{
		Reason: "Test",
	}
	w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/nonexistent/scale-to-zero", body)

	// Assert
	assert.Equal(t, http.StatusNotFound, w.Code)
	// Assert
	assert.Equal(t, http.StatusNotFound, w.Code)

	var response models.ScaleResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "error", response.Status)
	assert.Contains(t, response.Message, "not found")

	mockClient.AssertExpectations(t)
}

func TestScaleUp_Success(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-up", handler.ScaleUp)

	// Mock expectations
	status := &k8s.DeploymentStatus{
		Name:              "test-app",
		Namespace:         "test-ns",
		DesiredReplicas:   0,
		CurrentReplicas:   0,
		AvailableReplicas: 0,
		UpdatedReplicas:   0,
		CreationTime:      time.Now(),
	}
	mockClient.On("GetDeploymentStatus", mock.Anything, "test-ns", "test-app").Return(status, nil)
	mockClient.On("ScaleDeployment", mock.Anything, "test-ns", "test-app", int32(2)).Return(nil)
	// Test
	body := models.ScaleUpRequest{
		Replicas: 2,
		Reason:   "Resume operations",
	}
	w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/test-app/scale-up", body)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)

	var response models.ScaleResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "success", response.Status)
	assert.Equal(t, "Deployment scaled to 2 replicas", response.Message)
	assert.NotNil(t, response.Deployment)
	assert.Equal(t, int32(0), response.Deployment.PreviousReplicas)

	mockClient.AssertExpectations(t)
}

func TestScaleUp_InvalidReplicaCount(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-up", handler.ScaleUp)

	// Test cases
	testCases := []struct {
		name     string
		replicas int32
		error    string
	}{
		{
			name:     "Zero replicas",
			replicas: 0,
			error:    "Invalid replica count",
		},
		{
			name:     "Negative replicas",
			replicas: -1,
			error:    "Invalid replica count",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			body := models.ScaleUpRequest{
				Replicas: tc.replicas,
				Reason:   "Test",
			}
			w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/test-app/scale-up", body)

			// Assert
			assert.Equal(t, http.StatusBadRequest, w.Code)

			var response models.ScaleResponse
			helpers.ParseJSONResponse(t, w, &response)
			assert.Equal(t, "error", response.Status)
			assert.Equal(t, "Invalid request body", response.Message)
		})
	}
}

func TestGetStatus_Success(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.GET("/deployments/:namespace/:name/status", handler.GetStatus)

	// Mock expectations
	status := &k8s.DeploymentStatus{
		Name:              "test-app",
		Namespace:         "test-ns",
		DesiredReplicas:   3,
		CurrentReplicas:   2,
		AvailableReplicas: 2,
		UpdatedReplicas:   2,
		CreationTime:      time.Now().Add(-24 * time.Hour),
	}
	mockClient.On("GetDeploymentStatus", mock.Anything, "test-ns", "test-app").Return(status, nil)
	// Test
	w := helpers.MakeRequest(router, "GET", "/deployments/test-ns/test-app/status", nil)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)

	var response models.DeploymentStatusResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "success", response.Status)
	assert.NotNil(t, response.Deployment)
	assert.Equal(t, "test-app", response.Deployment.Name)
	assert.Equal(t, "test-ns", response.Deployment.Namespace)
	assert.Equal(t, int32(2), response.Deployment.CurrentReplicas)
	assert.Equal(t, int32(3), response.Deployment.DesiredReplicas)
	assert.Equal(t, int32(2), response.Deployment.AvailableReplicas)

	mockClient.AssertExpectations(t)
}

func TestGetStatus_NotFound(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.GET("/deployments/:namespace/:name/status", handler.GetStatus)

	// Mock expectations
	notFoundErr := &k8serrors.StatusError{
		ErrStatus: metav1.Status{
			Reason: metav1.StatusReasonNotFound,
			Code:   http.StatusNotFound,
		},
	}
	mockClient.On("GetDeploymentStatus", mock.Anything, "test-ns", "nonexistent").Return(nil, notFoundErr)

	// Test
	w := helpers.MakeRequest(router, "GET", "/deployments/test-ns/nonexistent/status", nil)

	// Assert
	assert.Equal(t, http.StatusNotFound, w.Code)

	var response models.DeploymentStatusResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, models.StatusError, response.Status)
	assert.Contains(t, response.Message, "Deployment test-ns/nonexistent not found")

	mockClient.AssertExpectations(t)
}

func TestScaleDeployment_ScaleError(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-to-zero", handler.ScaleToZero)

	// Mock expectations
	status := &k8s.DeploymentStatus{
		Name:              "test-app",
		Namespace:         "test-ns",
		DesiredReplicas:   3,
		CurrentReplicas:   3,
		AvailableReplicas: 3,
		UpdatedReplicas:   3,
		CreationTime:      time.Now(),
	}
	mockClient.On("GetDeploymentStatus", mock.Anything, "test-ns", "test-app").Return(status, nil)
	mockClient.On("ScaleDeployment", mock.Anything, "test-ns", "test-app", int32(0)).Return(fmt.Errorf("scaling failed"))

	// Test
	body := models.ScaleRequest{
		Reason: "Test",
	}
	w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/test-app/scale-to-zero", body)

	// Assert
	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var response models.ScaleResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, models.StatusError, response.Status)
	assert.Equal(t, "Failed to scale deployment", response.Message)

	mockClient.AssertExpectations(t)
}

func TestScaleToZero_InvalidJSON(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-to-zero", handler.ScaleToZero)

	// Test
	w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/test-app/scale-to-zero", "invalid json")

	// Assert
	assert.Equal(t, http.StatusBadRequest, w.Code)

	var response models.ScaleResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, models.StatusError, response.Status)
	assert.Contains(t, response.Error, "cannot unmarshal")
}

func TestScaleUp_InvalidJSON(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewDeploymentHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.POST("/deployments/:namespace/:name/scale-up", handler.ScaleUp)

	// Test
	w := helpers.MakeRequest(router, "POST", "/deployments/test-ns/test-app/scale-up", "invalid json")

	// Assert
	assert.Equal(t, http.StatusBadRequest, w.Code)

	var response models.ScaleResponse
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, models.StatusError, response.Status)
	assert.Contains(t, response.Error, "cannot unmarshal")
}
