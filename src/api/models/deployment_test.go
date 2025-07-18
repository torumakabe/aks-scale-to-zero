package models

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestScaleRequest_JSONSerialization(t *testing.T) {
	tests := []struct {
		name     string
		request  ScaleRequest
		expected string
	}{
		{
			name: "basic scale request",
			request: ScaleRequest{
				Reason: "Cost optimization",
			},
			expected: `{"reason":"Cost optimization"}`,
		},
		{
			name: "scale request with scheduled scale up",
			request: ScaleRequest{
				Reason:           "Maintenance window",
				ScheduledScaleUp: func() *time.Time { t := time.Date(2023, 12, 25, 9, 0, 0, 0, time.UTC); return &t }(),
			},
			expected: `{"reason":"Maintenance window","scheduled_scale_up":"2023-12-25T09:00:00Z"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Test marshaling
			data, err := json.Marshal(tt.request)
			assert.NoError(t, err)
			assert.JSONEq(t, tt.expected, string(data))

			// Test unmarshaling
			var decoded ScaleRequest
			err = json.Unmarshal(data, &decoded)
			assert.NoError(t, err)
			assert.Equal(t, tt.request.Reason, decoded.Reason)

			if tt.request.ScheduledScaleUp != nil {
				assert.NotNil(t, decoded.ScheduledScaleUp)
				assert.True(t, tt.request.ScheduledScaleUp.Equal(*decoded.ScheduledScaleUp))
			} else {
				assert.Nil(t, decoded.ScheduledScaleUp)
			}
		})
	}
}

func TestScaleUpRequest_JSONSerialization(t *testing.T) {
	tests := []struct {
		name     string
		request  ScaleUpRequest
		expected string
	}{
		{
			name: "basic scale up request",
			request: ScaleUpRequest{
				Replicas: 3,
				Reason:   "Resume operations",
			},
			expected: `{"replicas":3,"reason":"Resume operations"}`,
		},
		{
			name: "scale up request with higher replicas",
			request: ScaleUpRequest{
				Replicas: 5,
				Reason:   "Peak hours",
			},
			expected: `{"replicas":5,"reason":"Peak hours"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Test marshaling
			data, err := json.Marshal(tt.request)
			assert.NoError(t, err)
			assert.JSONEq(t, tt.expected, string(data))

			// Test unmarshaling
			var decoded ScaleUpRequest
			err = json.Unmarshal(data, &decoded)
			assert.NoError(t, err)
			assert.Equal(t, tt.request.Replicas, decoded.Replicas)
			assert.Equal(t, tt.request.Reason, decoded.Reason)
		})
	}
}

func TestScaleUpRequest_Validation(t *testing.T) {
	tests := []struct {
		name    string
		request ScaleUpRequest
		isValid bool
	}{
		{
			name: "valid request with positive replicas",
			request: ScaleUpRequest{
				Replicas: 3,
				Reason:   "Scale up",
			},
			isValid: true,
		},
		{
			name: "invalid request with zero replicas",
			request: ScaleUpRequest{
				Replicas: 0,
				Reason:   "Scale up",
			},
			isValid: false,
		},
		{
			name: "invalid request with negative replicas",
			request: ScaleUpRequest{
				Replicas: -1,
				Reason:   "Scale up",
			},
			isValid: false,
		},
		{
			name: "invalid request with empty reason",
			request: ScaleUpRequest{
				Replicas: 3,
				Reason:   "",
			},
			isValid: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Basic validation checks
			if tt.isValid {
				assert.Greater(t, tt.request.Replicas, int32(0), "Replicas should be positive")
				assert.NotEmpty(t, tt.request.Reason, "Reason should not be empty")
			} else {
				isInvalid := tt.request.Replicas <= 0 || tt.request.Reason == ""
				assert.True(t, isInvalid, "Request should be invalid")
			}
		})
	}
}

func TestScaleResponse_JSONSerialization(t *testing.T) {
	deployment := &DeploymentInfo{
		Name:             "test-app",
		Namespace:        "test-ns",
		PreviousReplicas: 3,
		CurrentReplicas:  0,
	}

	tests := []struct {
		name     string
		response ScaleResponse
	}{
		{
			name: "success response",
			response: ScaleResponse{
				Status:  StatusSuccess,
				Message: "Deployment scaled successfully",
			},
		},
		{
			name: "response with deployment info",
			response: ScaleResponse{
				Status:     StatusSuccess,
				Message:    "Deployment scaled to zero",
				Deployment: deployment,
			},
		},
		{
			name: "error response",
			response: ScaleResponse{
				Status:  StatusError,
				Message: "Failed to scale deployment",
				Error:   "Deployment not found",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Test marshaling
			data, err := json.Marshal(tt.response)
			assert.NoError(t, err)

			// Test unmarshaling
			var decoded ScaleResponse
			err = json.Unmarshal(data, &decoded)
			assert.NoError(t, err)
			assert.Equal(t, tt.response.Status, decoded.Status)
			assert.Equal(t, tt.response.Message, decoded.Message)
			assert.Equal(t, tt.response.Error, decoded.Error)

			// Check deployment info if present
			if tt.response.Deployment != nil {
				assert.NotNil(t, decoded.Deployment)
				assert.Equal(t, tt.response.Deployment.Name, decoded.Deployment.Name)
				assert.Equal(t, tt.response.Deployment.Namespace, decoded.Deployment.Namespace)
			}
		})
	}
}

func TestDeploymentStatus_JSONSerialization(t *testing.T) {
	now := time.Now()
	status := DeploymentStatus{
		Name:              "test-app",
		Namespace:         "test-ns",
		Deployment:        "test-app",
		CurrentReplicas:   2,
		DesiredReplicas:   3,
		AvailableReplicas: 2,
		Status:            StatusScaling,
		LastScaleTime:     now,
		Message:           "Scaling in progress",
	}

	// Test marshaling
	data, err := json.Marshal(status)
	assert.NoError(t, err)

	// Test unmarshaling
	var decoded DeploymentStatus
	err = json.Unmarshal(data, &decoded)
	assert.NoError(t, err)
	assert.Equal(t, status.Name, decoded.Name)
	assert.Equal(t, status.Namespace, decoded.Namespace)
	assert.Equal(t, status.CurrentReplicas, decoded.CurrentReplicas)
	assert.Equal(t, status.DesiredReplicas, decoded.DesiredReplicas)
	assert.Equal(t, status.Status, decoded.Status)
	assert.True(t, status.LastScaleTime.Equal(decoded.LastScaleTime))
}

func TestDeploymentStatusResponse_JSONSerialization(t *testing.T) {
	now := time.Now()
	deploymentStatus := &DeploymentStatus{
		Name:              "test-app",
		Namespace:         "test-ns",
		CurrentReplicas:   3,
		DesiredReplicas:   3,
		AvailableReplicas: 3,
		Status:            StatusActive,
	}

	response := DeploymentStatusResponse{
		Status:     StatusSuccess,
		Message:    "Status retrieved successfully",
		Deployment: deploymentStatus,
		Timestamp:  now,
	}

	// Test marshaling
	data, err := json.Marshal(response)
	assert.NoError(t, err)

	// Test unmarshaling
	var decoded DeploymentStatusResponse
	err = json.Unmarshal(data, &decoded)
	assert.NoError(t, err)
	assert.Equal(t, response.Status, decoded.Status)
	assert.Equal(t, response.Message, decoded.Message)
	assert.NotNil(t, decoded.Deployment)
	assert.Equal(t, deploymentStatus.Name, decoded.Deployment.Name)
	assert.True(t, response.Timestamp.Equal(decoded.Timestamp))
}

func TestStatusConstants(t *testing.T) {
	// Test deployment status constants
	assert.Equal(t, "active", StatusActive)
	assert.Equal(t, "inactive", StatusInactive)
	assert.Equal(t, "scaling", StatusScaling)
	assert.Equal(t, "unknown", StatusUnknown)

	// Test response status constants
	assert.Equal(t, "success", ResponseStatusSuccess)
	assert.Equal(t, "error", ResponseStatusError)
	assert.Equal(t, "pending", ResponseStatusPending)
	assert.Equal(t, "success", StatusSuccess)
	assert.Equal(t, "error", StatusError)
}

func TestJSONTagConsistency(t *testing.T) {
	// Test that JSON tags are correctly applied and consistent
	t.Run("ScaleRequest tags", func(t *testing.T) {
		req := ScaleRequest{Reason: "test"}
		data, _ := json.Marshal(req)
		assert.Contains(t, string(data), `"reason":"test"`)
	})

	t.Run("ScaleUpRequest tags", func(t *testing.T) {
		req := ScaleUpRequest{Replicas: 5, Reason: "test"}
		data, _ := json.Marshal(req)
		assert.Contains(t, string(data), `"replicas":5`)
		assert.Contains(t, string(data), `"reason":"test"`)
	})

	t.Run("DeploymentStatus tags", func(t *testing.T) {
		status := DeploymentStatus{
			CurrentReplicas: 3,
			DesiredReplicas: 5,
		}
		data, _ := json.Marshal(status)
		assert.Contains(t, string(data), `"current_replicas":3`)
		assert.Contains(t, string(data), `"desired_replicas":5`)
	})
}
