package middleware

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestStructuredLogger(t *testing.T) {
	// Set Gin to test mode
	gin.SetMode(gin.TestMode)

	// Capture log output
	var logBuffer bytes.Buffer
	oldLogger := log.Writer()
	log.SetOutput(&logBuffer)
	defer log.SetOutput(oldLogger)

	// Create test router
	router := gin.New()
	router.Use(RequestIDMiddleware())
	router.Use(StructuredLogger())

	// Add test endpoint
	router.GET("/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "test"})
	})

	// Make request
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("User-Agent", "test-agent")
	router.ServeHTTP(w, req)

	// Parse log output
	var logEntry LogEntry
	logOutput := logBuffer.String()
	assert.NotEmpty(t, logOutput)

	// Extract JSON from log output (skip timestamp prefix)
	jsonStart := bytes.IndexByte(logBuffer.Bytes(), '{')
	if jsonStart >= 0 {
		err := json.Unmarshal(logBuffer.Bytes()[jsonStart:], &logEntry)
		assert.NoError(t, err)

		// Verify log entry
		assert.Equal(t, "GET", logEntry.Method)
		assert.Equal(t, "/test", logEntry.Path)
		assert.Equal(t, 200, logEntry.StatusCode)
		assert.Equal(t, "test-agent", logEntry.UserAgent)
		assert.NotEmpty(t, logEntry.Timestamp)
		assert.NotEmpty(t, logEntry.Latency)
		assert.NotEmpty(t, logEntry.RequestID)
	}
}

func TestRequestIDMiddleware(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := gin.New()
	router.Use(RequestIDMiddleware())

	router.GET("/test", func(c *gin.Context) {
		requestID := c.GetString("RequestID")
		c.JSON(http.StatusOK, gin.H{"request_id": requestID})
	})

	t.Run("generates request ID when not provided", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/test", nil)
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		assert.NotEmpty(t, w.Header().Get("X-Request-ID"))

		var response map[string]string
		err := json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		assert.NotEmpty(t, response["request_id"])
	})

	t.Run("uses provided request ID", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/test", nil)
		req.Header.Set("X-Request-ID", "test-request-id")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		assert.Equal(t, "test-request-id", w.Header().Get("X-Request-ID"))

		var response map[string]string
		err := json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		assert.Equal(t, "test-request-id", response["request_id"])
	})
}
