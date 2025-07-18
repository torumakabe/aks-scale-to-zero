package handlers

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/torumakabe/aks-scale-to-zero/api/k8s"
	"github.com/torumakabe/aks-scale-to-zero/api/models"
)

// DeploymentHandler handles deployment-related requests
type DeploymentHandler struct {
	k8sClient k8s.ClientInterface
}

// NewDeploymentHandler creates a new deployment handler
func NewDeploymentHandler(k8sClient k8s.ClientInterface) *DeploymentHandler {
	return &DeploymentHandler{
		k8sClient: k8sClient,
	}
}

// ScaleToZero handles POST /api/v1/deployments/{namespace}/{name}/scale-to-zero
func (h *DeploymentHandler) ScaleToZero(c *gin.Context) {
	namespace := c.Param("namespace")
	name := c.Param("name")

	var req models.ScaleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ScaleResponse{
			Status:  models.StatusError,
			Message: "Invalid request body",
			Error:   err.Error(),
		})
		return
	}

	// Get current deployment status
	status, err := h.k8sClient.GetDeploymentStatus(c.Request.Context(), namespace, name)
	if err != nil {
		c.JSON(http.StatusNotFound, models.ScaleResponse{
			Status:  models.StatusError,
			Message: fmt.Sprintf("Deployment %s/%s not found", namespace, name),
			Error:   err.Error(),
		})
		return
	}

	previousReplicas := status.DesiredReplicas

	// Scale to zero
	err = h.k8sClient.ScaleDeployment(c.Request.Context(), namespace, name, 0)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.ScaleResponse{
			Status:  models.StatusError,
			Message: "Failed to scale deployment",
			Error:   err.Error(),
		})
		return
	}

	response := models.ScaleResponse{
		Status:    models.StatusSuccess,
		Message:   "Deployment scaled to zero",
		Timestamp: time.Now().UTC(),
		Deployment: &models.DeploymentInfo{
			Name:             name,
			Namespace:        namespace,
			PreviousReplicas: previousReplicas,
			CurrentReplicas:  0,
			TargetReplicas:   0,
			TargetStatus:     "scaled-to-zero",
			ScalingReason:    req.Reason,
			ScheduledScaleUp: req.ScheduledScaleUp,
		},
	}

	c.JSON(http.StatusOK, response)
}

// ScaleUp handles POST /api/v1/deployments/{namespace}/{name}/scale-up
func (h *DeploymentHandler) ScaleUp(c *gin.Context) {
	namespace := c.Param("namespace")
	name := c.Param("name")

	var req models.ScaleUpRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ScaleResponse{
			Status:  models.StatusError,
			Message: "Invalid request body",
			Error:   err.Error(),
		})
		return
	}

	// Get current deployment status
	status, err := h.k8sClient.GetDeploymentStatus(c.Request.Context(), namespace, name)
	if err != nil {
		c.JSON(http.StatusNotFound, models.ScaleResponse{
			Status:  models.StatusError,
			Message: fmt.Sprintf("Deployment %s/%s not found", namespace, name),
			Error:   err.Error(),
		})
		return
	}

	previousReplicas := status.DesiredReplicas

	// Scale up
	err = h.k8sClient.ScaleDeployment(c.Request.Context(), namespace, name, req.Replicas)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.ScaleResponse{
			Status:  models.StatusError,
			Message: "Failed to scale deployment",
			Error:   err.Error(),
		})
		return
	}

	response := models.ScaleResponse{
		Status:    models.StatusSuccess,
		Message:   fmt.Sprintf("Deployment scaled to %d replicas", req.Replicas),
		Timestamp: time.Now().UTC(),
		Deployment: &models.DeploymentInfo{
			Name:             name,
			Namespace:        namespace,
			PreviousReplicas: previousReplicas,
			CurrentReplicas:  status.CurrentReplicas,
			TargetReplicas:   req.Replicas,
			TargetStatus:     "scaling-up",
			ScalingReason:    req.Reason,
		},
	}

	c.JSON(http.StatusOK, response)
}

// GetStatus handles GET /api/v1/deployments/{namespace}/{name}/status
func (h *DeploymentHandler) GetStatus(c *gin.Context) {
	namespace := c.Param("namespace")
	name := c.Param("name")

	status, err := h.k8sClient.GetDeploymentStatus(c.Request.Context(), namespace, name)
	if err != nil {
		c.JSON(http.StatusNotFound, models.DeploymentStatusResponse{
			Status:    models.StatusError,
			Message:   fmt.Sprintf("Deployment %s/%s not found", namespace, name),
			Error:     err.Error(),
			Timestamp: time.Now(),
		})
		return
	}

	// Determine status
	deploymentStatus := models.StatusActive
	if status.DesiredReplicas == 0 {
		deploymentStatus = models.StatusInactive
	} else if status.CurrentReplicas != status.DesiredReplicas {
		deploymentStatus = models.StatusScaling
	}

	deploymentInfo := &models.DeploymentStatus{
		Name:              status.Name,
		Namespace:         status.Namespace,
		Deployment:        name,
		CurrentReplicas:   status.CurrentReplicas,
		DesiredReplicas:   status.DesiredReplicas,
		AvailableReplicas: status.AvailableReplicas,
		Status:            deploymentStatus,
		LastScaleTime:     status.CreationTime,
	}

	response := models.DeploymentStatusResponse{
		Status:     models.StatusSuccess,
		Message:    "Deployment status retrieved successfully",
		Deployment: deploymentInfo,
		Timestamp:  time.Now(),
	}

	c.JSON(http.StatusOK, response)
}
