package utils

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// Response represents a standard API response
type Response struct {
	Success   bool        `json:"success"`
	Message   string      `json:"message,omitempty"`
	Data      interface{} `json:"data,omitempty"`
	Error     string      `json:"error,omitempty"`
	Timestamp time.Time   `json:"timestamp"`
}

// ErrorDetail represents detailed error information
type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Field   string `json:"field,omitempty"`
}

// ValidationError represents validation errors
type ValidationError struct {
	Errors []ErrorDetail `json:"errors"`
}

// SendSuccess sends a successful response
func SendSuccess(c *gin.Context, statusCode int, message string, data interface{}) {
	c.JSON(statusCode, Response{
		Success:   true,
		Message:   message,
		Data:      data,
		Timestamp: time.Now().UTC(),
	})
}

// SendError sends an error response
func SendError(c *gin.Context, statusCode int, message string, err error) {
	errorMessage := ""
	if err != nil {
		errorMessage = err.Error()
	}

	c.JSON(statusCode, Response{
		Success:   false,
		Message:   message,
		Error:     errorMessage,
		Timestamp: time.Now().UTC(),
	})
}

// SendValidationError sends validation error response
func SendValidationError(c *gin.Context, errors []ErrorDetail) {
	c.JSON(http.StatusBadRequest, Response{
		Success: false,
		Message: "Validation failed",
		Data: ValidationError{
			Errors: errors,
		},
		Timestamp: time.Now().UTC(),
	})
}

// Success helper functions
func OK(c *gin.Context, message string, data interface{}) {
	SendSuccess(c, http.StatusOK, message, data)
}

func Created(c *gin.Context, message string, data interface{}) {
	SendSuccess(c, http.StatusCreated, message, data)
}

func Accepted(c *gin.Context, message string, data interface{}) {
	SendSuccess(c, http.StatusAccepted, message, data)
}

func NoContent(c *gin.Context) {
	c.Status(http.StatusNoContent)
}

// Error helper functions
func BadRequest(c *gin.Context, message string, err error) {
	SendError(c, http.StatusBadRequest, message, err)
}

func Unauthorized(c *gin.Context, message string) {
	SendError(c, http.StatusUnauthorized, message, nil)
}

func Forbidden(c *gin.Context, message string) {
	SendError(c, http.StatusForbidden, message, nil)
}

func NotFound(c *gin.Context, message string) {
	SendError(c, http.StatusNotFound, message, nil)
}

func InternalServerError(c *gin.Context, message string, err error) {
	SendError(c, http.StatusInternalServerError, message, err)
}

func ServiceUnavailable(c *gin.Context, message string, err error) {
	SendError(c, http.StatusServiceUnavailable, message, err)
}

// Paginated response helper
type PaginatedResponse struct {
	Items      interface{} `json:"items"`
	Total      int         `json:"total"`
	Page       int         `json:"page"`
	PerPage    int         `json:"per_page"`
	TotalPages int         `json:"total_pages"`
}

func SendPaginated(c *gin.Context, items interface{}, total, page, perPage int) {
	totalPages := (total + perPage - 1) / perPage

	OK(c, "Data retrieved successfully", PaginatedResponse{
		Items:      items,
		Total:      total,
		Page:       page,
		PerPage:    perPage,
		TotalPages: totalPages,
	})
}
