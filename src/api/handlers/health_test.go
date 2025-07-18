package handlers

import (
	"net/http"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/torumakabe/aks-scale-to-zero/api/testing/helpers"
	"github.com/torumakabe/aks-scale-to-zero/api/testing/mocks"
	"k8s.io/client-go/kubernetes/fake"
)

func TestHealth_Success(t *testing.T) {
	// Setup
	handler := NewHealthHandler(nil) // Health check doesn't need k8s client
	router := helpers.SetupTestRouter()
	router.GET("/health", handler.Health)

	// Test
	w := helpers.MakeRequest(router, "GET", "/health", nil)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)

	var response gin.H
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "healthy", response["status"])
}

func TestReady_Success(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewHealthHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.GET("/ready", handler.Ready)

	// Mock expectations - simulate successful k8s connection
	fakeClientset := fake.NewSimpleClientset()
	mockClient.On("GetClientset").Return(fakeClientset)

	// Test
	w := helpers.MakeRequest(router, "GET", "/ready", nil)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)

	var response gin.H
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "ready", response["status"])
	assert.Equal(t, "connected", response["kubernetes"])

	mockClient.AssertExpectations(t)
}

func TestReady_K8sConnectionFailed(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewHealthHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.GET("/ready", handler.Ready)

	// Mock expectations - simulate failed k8s connection
	mockClient.On("GetClientset").Return(nil)

	// Test
	w := helpers.MakeRequest(router, "GET", "/ready", nil)

	// Assert
	assert.Equal(t, http.StatusServiceUnavailable, w.Code)

	var response gin.H
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "not ready", response["status"])
	assert.Equal(t, "Kubernetes client not available", response["error"])

	mockClient.AssertExpectations(t)
}

func TestReady_NoK8sClient(t *testing.T) {
	// Setup
	handler := NewHealthHandler(nil) // No k8s client provided
	router := helpers.SetupTestRouter()
	router.GET("/ready", handler.Ready)

	// Test
	w := helpers.MakeRequest(router, "GET", "/ready", nil)

	// Assert
	assert.Equal(t, http.StatusServiceUnavailable, w.Code)

	var response gin.H
	helpers.ParseJSONResponse(t, w, &response)
	assert.Equal(t, "not ready", response["status"])
	assert.Equal(t, "Kubernetes client not available", response["error"])
}

func TestReady_K8sAPIUnreachable(t *testing.T) {
	// This test requires complex mocking that is not easily achievable with current setup
	// TODO: Implement proper error simulation for kubernetes connectivity
	t.Skip("Kubernetes API error testing requires more sophisticated mock setup")
}

// Test concurrent requests to health endpoints
func TestHealthEndpoints_Concurrent(t *testing.T) {
	// Setup
	mockClient := mocks.NewMockK8sClient()
	handler := NewHealthHandler(mockClient)
	router := helpers.SetupTestRouter()
	router.GET("/health", handler.Health)
	router.GET("/ready", handler.Ready)

	// Mock expectations
	fakeClientset := fake.NewSimpleClientset()
	mockClient.On("GetClientset").Return(fakeClientset)

	// Test concurrent requests
	done := make(chan bool, 20)

	for i := 0; i < 10; i++ {
		go func() {
			w := helpers.MakeRequest(router, "GET", "/health", nil)
			assert.Equal(t, http.StatusOK, w.Code)
			done <- true
		}()

		go func() {
			w := helpers.MakeRequest(router, "GET", "/ready", nil)
			assert.Equal(t, http.StatusOK, w.Code)
			done <- true
		}()
	}

	// Wait for all goroutines to complete
	for i := 0; i < 20; i++ {
		<-done
	}

	// Verify mock calls (should be called at least 10 times for readiness checks)
	mockClient.AssertExpectations(t)
}
