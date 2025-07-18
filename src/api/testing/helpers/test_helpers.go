package helpers

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// SetupTestRouter creates a test router with gin in test mode
func SetupTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	return router
}

// MakeRequest performs an HTTP request and returns the response
func MakeRequest(router *gin.Engine, method, path string, body interface{}) *httptest.ResponseRecorder {
	var reqBody io.Reader
	if body != nil {
		jsonBytes, _ := json.Marshal(body)
		reqBody = bytes.NewBuffer(jsonBytes)
	}

	req, _ := http.NewRequest(method, path, reqBody)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

// MakeAuthenticatedRequest performs an HTTP request with authentication
func MakeAuthenticatedRequest(router *gin.Engine, method, path string, body interface{}, apiKey string) *httptest.ResponseRecorder {
	var reqBody io.Reader
	if body != nil {
		jsonBytes, _ := json.Marshal(body)
		reqBody = bytes.NewBuffer(jsonBytes)
	}

	req, _ := http.NewRequest(method, path, reqBody)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

// AssertJSONResponse validates JSON response
func AssertJSONResponse(t *testing.T, w *httptest.ResponseRecorder, expectedStatus int, expectedBody interface{}) {
	assert.Equal(t, expectedStatus, w.Code)

	if expectedBody != nil {
		var actual interface{}
		err := json.Unmarshal(w.Body.Bytes(), &actual)
		assert.NoError(t, err)

		expected, err := json.Marshal(expectedBody)
		assert.NoError(t, err)

		var expectedJSON interface{}
		err = json.Unmarshal(expected, &expectedJSON)
		assert.NoError(t, err)

		assert.Equal(t, expectedJSON, actual)
	}
}

// ParseJSONResponse parses JSON response into target struct
func ParseJSONResponse(t *testing.T, w *httptest.ResponseRecorder, target interface{}) {
	err := json.Unmarshal(w.Body.Bytes(), target)
	assert.NoError(t, err)
}
