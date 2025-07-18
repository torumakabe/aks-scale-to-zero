package middleware

import (
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

// AuthConfig holds authentication configuration
type AuthConfig struct {
	APIKey           string
	ExcludedPaths    []string
	ExcludedPrefixes []string
}

// NewAuthConfig creates a new auth configuration from environment
func NewAuthConfig() *AuthConfig {
	return &AuthConfig{
		APIKey: os.Getenv("API_KEY"),
		ExcludedPaths: []string{
			"/health",
			"/ready",
		},
		ExcludedPrefixes: []string{
			"/swagger/",
			"/docs/",
		},
	}
}

// APIKeyAuth returns a middleware for API key authentication
func APIKeyAuth(config *AuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check if authentication is disabled
		if config.APIKey == "" {
			c.Next()
			return
		}

		// Check if path is excluded
		path := c.Request.URL.Path
		if isPathExcluded(path, config.ExcludedPaths, config.ExcludedPrefixes) {
			c.Next()
			return
		}

		// Get API key from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Authorization header required",
			})
			c.Abort()
			return
		}

		// Check Bearer token format
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Invalid authorization format. Use: Bearer <api-key>",
			})
			c.Abort()
			return
		}

		// Validate API key
		if parts[1] != config.APIKey {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Invalid API key",
			})
			c.Abort()
			return
		}

		// Authentication successful
		c.Next()
	}
}

// isPathExcluded checks if a path should be excluded from authentication
func isPathExcluded(path string, excludedPaths []string, excludedPrefixes []string) bool {
	// Check exact path matches
	for _, excluded := range excludedPaths {
		if path == excluded {
			return true
		}
	}

	// Check prefix matches
	for _, prefix := range excludedPrefixes {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}

	return false
}

// RequireNamespace returns a middleware that validates namespace access
func RequireNamespace(allowedNamespaces []string) gin.HandlerFunc {
	return func(c *gin.Context) {
		namespace := c.Param("namespace")
		if namespace == "" {
			c.Next()
			return
		}

		// If no allowed namespaces specified, allow all
		if len(allowedNamespaces) == 0 {
			c.Next()
			return
		}

		// Check if namespace is allowed
		for _, allowed := range allowedNamespaces {
			if namespace == allowed {
				c.Next()
				return
			}
		}

		// Namespace not allowed
		c.JSON(http.StatusForbidden, gin.H{
			"error":     "Access to namespace denied",
			"namespace": namespace,
		})
		c.Abort()
	}
}
