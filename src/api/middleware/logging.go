package middleware

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// LogEntry represents a structured log entry
type LogEntry struct {
	Timestamp    string                 `json:"timestamp"`
	Method       string                 `json:"method"`
	Path         string                 `json:"path"`
	StatusCode   int                    `json:"status_code"`
	Latency      string                 `json:"latency"`
	ClientIP     string                 `json:"client_ip"`
	UserAgent    string                 `json:"user_agent"`
	RequestID    string                 `json:"request_id,omitempty"`
	RequestBody  map[string]interface{} `json:"request_body,omitempty"`
	ResponseBody map[string]interface{} `json:"response_body,omitempty"`
	Error        string                 `json:"error,omitempty"`
}

// bodyLogWriter is a custom response writer that captures the response body
type bodyLogWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (w bodyLogWriter) Write(b []byte) (int, error) {
	w.body.Write(b)
	return w.ResponseWriter.Write(b)
}

// StructuredLogger returns a gin middleware for structured JSON logging
func StructuredLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Start timer
		start := time.Now()

		// Read request body if present
		var requestBody map[string]interface{}
		if c.Request.Body != nil && c.Request.Method != "GET" {
			bodyBytes, _ := io.ReadAll(c.Request.Body)
			c.Request.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))

			// Try to parse as JSON
			if len(bodyBytes) > 0 {
				if err := json.Unmarshal(bodyBytes, &requestBody); err != nil {
					// Not a JSON body, ignore
					requestBody = nil
				}
			}
		}

		// Create custom response writer to capture response
		blw := &bodyLogWriter{body: bytes.NewBufferString(""), ResponseWriter: c.Writer}
		c.Writer = blw

		// Process request
		c.Next()

		// Calculate latency
		latency := time.Since(start)

		// Parse response body if JSON
		var responseBody map[string]interface{}
		if blw.body.Len() > 0 {
			if err := json.Unmarshal(blw.body.Bytes(), &responseBody); err != nil {
				// Not a JSON body, ignore
				responseBody = nil
			}
		}

		// Create log entry
		entry := LogEntry{
			Timestamp:  time.Now().UTC().Format(time.RFC3339),
			Method:     c.Request.Method,
			Path:       c.Request.URL.Path,
			StatusCode: c.Writer.Status(),
			Latency:    latency.String(),
			ClientIP:   c.ClientIP(),
			UserAgent:  c.Request.UserAgent(),
			RequestID:  c.GetString("RequestID"),
		}

		// Add request body for non-GET requests
		if c.Request.Method != "GET" && requestBody != nil {
			entry.RequestBody = requestBody
		}

		// Add response body for non-successful responses
		if c.Writer.Status() >= 400 && responseBody != nil {
			entry.ResponseBody = responseBody
		}

		// Add error if present
		if len(c.Errors) > 0 {
			entry.Error = c.Errors.String()
		}

		// Output as JSON
		jsonLog, _ := json.Marshal(entry)
		log.Println(string(jsonLog))
	}
}

// RequestIDMiddleware adds a unique request ID to each request
func RequestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = generateRequestID()
		}
		c.Set("RequestID", requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	}
}

// generateRequestID generates a simple request ID
func generateRequestID() string {
	return time.Now().Format("20060102150405") + "-" + randomString(8)
}

// randomString generates a random string of specified length
func randomString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[time.Now().UnixNano()%int64(len(charset))]
	}
	return string(b)
}
