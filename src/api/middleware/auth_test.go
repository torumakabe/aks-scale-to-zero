package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestAPIKeyAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name           string
		apiKey         string
		authHeader     string
		path           string
		expectedStatus int
		expectedBody   string
	}{
		{
			name:           "no API key configured allows all requests",
			apiKey:         "",
			authHeader:     "",
			path:           "/api/v1/test",
			expectedStatus: http.StatusOK,
			expectedBody:   "success",
		},
		{
			name:           "excluded path without auth",
			apiKey:         "test-key",
			authHeader:     "",
			path:           "/health",
			expectedStatus: http.StatusOK,
			expectedBody:   "healthy",
		},
		{
			name:           "protected path without auth",
			apiKey:         "test-key",
			authHeader:     "",
			path:           "/api/v1/test",
			expectedStatus: http.StatusUnauthorized,
			expectedBody:   "Authorization header required",
		},
		{
			name:           "protected path with invalid format",
			apiKey:         "test-key",
			authHeader:     "test-key",
			path:           "/api/v1/test",
			expectedStatus: http.StatusUnauthorized,
			expectedBody:   "Invalid authorization format",
		},
		{
			name:           "protected path with wrong key",
			apiKey:         "test-key",
			authHeader:     "Bearer wrong-key",
			path:           "/api/v1/test",
			expectedStatus: http.StatusUnauthorized,
			expectedBody:   "Invalid API key",
		},
		{
			name:           "protected path with correct key",
			apiKey:         "test-key",
			authHeader:     "Bearer test-key",
			path:           "/api/v1/test",
			expectedStatus: http.StatusOK,
			expectedBody:   "success",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := &AuthConfig{
				APIKey:           tt.apiKey,
				ExcludedPaths:    []string{"/health", "/ready"},
				ExcludedPrefixes: []string{"/swagger/", "/docs/"},
			}

			router := gin.New()
			router.Use(APIKeyAuth(config))

			// Add test endpoints
			router.GET("/health", func(c *gin.Context) {
				c.JSON(http.StatusOK, gin.H{"status": "healthy"})
			})
			router.GET("/api/v1/test", func(c *gin.Context) {
				c.JSON(http.StatusOK, gin.H{"message": "success"})
			})

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", tt.path, nil)
			if tt.authHeader != "" {
				req.Header.Set("Authorization", tt.authHeader)
			}

			router.ServeHTTP(w, req)

			assert.Equal(t, tt.expectedStatus, w.Code)
			assert.Contains(t, w.Body.String(), tt.expectedBody)
		})
	}
}

func TestRequireNamespace(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name              string
		allowedNamespaces []string
		namespace         string
		expectedStatus    int
	}{
		{
			name:              "no namespaces configured allows all",
			allowedNamespaces: []string{},
			namespace:         "any-namespace",
			expectedStatus:    http.StatusOK,
		},
		{
			name:              "allowed namespace",
			allowedNamespaces: []string{"default", "project-a"},
			namespace:         "default",
			expectedStatus:    http.StatusOK,
		},
		{
			name:              "denied namespace",
			allowedNamespaces: []string{"default", "project-a"},
			namespace:         "project-b",
			expectedStatus:    http.StatusForbidden,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.Use(RequireNamespace(tt.allowedNamespaces))

			router.GET("/deployments/:namespace/:name", func(c *gin.Context) {
				c.JSON(http.StatusOK, gin.H{"namespace": c.Param("namespace")})
			})

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/deployments/"+tt.namespace+"/test", nil)
			router.ServeHTTP(w, req)

			assert.Equal(t, tt.expectedStatus, w.Code)
		})
	}
}
