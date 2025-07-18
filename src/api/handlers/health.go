package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/torumakabe/aks-scale-to-zero/api/k8s"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// HealthHandler handles health check requests
type HealthHandler struct {
	k8sClient k8s.ClientInterface
}

// NewHealthHandler creates a new health handler
func NewHealthHandler(k8sClient k8s.ClientInterface) *HealthHandler {
	return &HealthHandler{
		k8sClient: k8sClient,
	}
}

// Health handles GET /health - basic health check
func (h *HealthHandler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "healthy",
		"time":   time.Now().UTC().Format(time.RFC3339),
	})
}

// Ready handles GET /ready - readiness check including Kubernetes connectivity
func (h *HealthHandler) Ready(c *gin.Context) {
	// Check if k8s client is available
	if h.k8sClient == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "not ready",
			"error":  "Kubernetes client not available",
			"time":   time.Now().UTC().Format(time.RFC3339),
		})
		return
	}

	// Check if we can connect to Kubernetes API
	clientset := h.k8sClient.GetClientset()
	if clientset == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "not ready",
			"error":  "Kubernetes client not available",
			"time":   time.Now().UTC().Format(time.RFC3339),
		})
		return
	}

	// Try to list deployments in scale-system namespace as a connectivity check
	// We use deployments because the service account has permissions for this resource
	_, err := clientset.AppsV1().Deployments("scale-system").List(c.Request.Context(), metav1.ListOptions{Limit: 1})
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "not ready",
			"error":  "unable to connect to Kubernetes API",
			"time":   time.Now().UTC().Format(time.RFC3339),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":     "ready",
		"kubernetes": "connected",
		"time":       time.Now().UTC().Format(time.RFC3339),
	})
}
