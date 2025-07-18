package models

import (
	"time"
)

// ScaleRequest represents the request payload for scaling operations
type ScaleRequest struct {
	Reason           string     `json:"reason" validate:"required,min=1,max=500"`
	ScheduledScaleUp *time.Time `json:"scheduled_scale_up,omitempty" validate:"omitempty"`
}

// ScaleUpRequest represents the request payload for scale-up operations
type ScaleUpRequest struct {
	Replicas int32  `json:"replicas" binding:"required,min=1" validate:"required,min=1"`
	Reason   string `json:"reason" binding:"required,min=1,max=500" validate:"required,min=1,max=500"`
}

// ScaleResponse represents the response for scaling operations
type ScaleResponse struct {
	Status     string          `json:"status"`
	Message    string          `json:"message"`
	Deployment *DeploymentInfo `json:"deployment,omitempty"`
	Error      string          `json:"error,omitempty"`
	Timestamp  time.Time       `json:"timestamp"`
}

// DeploymentInfo contains information about the deployment
type DeploymentInfo struct {
	Name             string     `json:"name"`
	Namespace        string     `json:"namespace"`
	Replicas         int32      `json:"replicas"`
	PreviousReplicas int32      `json:"previous_replicas"`
	CurrentReplicas  int32      `json:"current_replicas"`
	TargetReplicas   int32      `json:"target_replicas"`
	TargetStatus     string     `json:"target_status"`
	ScaledAt         time.Time  `json:"scaled_at"`
	ScaledBy         string     `json:"scaled_by,omitempty"`
	Reason           string     `json:"reason,omitempty"`
	ScalingReason    string     `json:"scaling_reason,omitempty"`
	ScheduledScaleUp *time.Time `json:"scheduled_scale_up,omitempty"`
}

// DeploymentStatus represents the current status of a deployment
type DeploymentStatus struct {
	Name              string    `json:"name"`
	Namespace         string    `json:"namespace"`
	Deployment        string    `json:"deployment"`
	CurrentReplicas   int32     `json:"current_replicas"`
	DesiredReplicas   int32     `json:"desired_replicas"`
	AvailableReplicas int32     `json:"available_replicas"`
	Status            string    `json:"status"`
	LastScaled        time.Time `json:"last_scaled,omitempty"`
	LastScaleTime     time.Time `json:"last_scale_time,omitempty"`
	Message           string    `json:"message,omitempty"`
}

// DeploymentStatusResponse represents the response for deployment status requests
type DeploymentStatusResponse struct {
	Status     string            `json:"status"`
	Message    string            `json:"message"`
	Deployment *DeploymentStatus `json:"deployment,omitempty"`
	Error      string            `json:"error,omitempty"`
	Timestamp  time.Time         `json:"timestamp"`
}

// Constants for deployment status
const (
	StatusActive   = "active"
	StatusInactive = "inactive"
	StatusScaling  = "scaling"
	StatusUnknown  = "unknown"
)

// Constants for scale response status
const (
	ResponseStatusSuccess = "success"
	ResponseStatusError   = "error"
	ResponseStatusPending = "pending"
	StatusSuccess         = "success"
	StatusError           = "error"
)
