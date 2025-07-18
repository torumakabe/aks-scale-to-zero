package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/torumakabe/aks-scale-to-zero/api/handlers"
	"github.com/torumakabe/aks-scale-to-zero/api/k8s"
	"github.com/torumakabe/aks-scale-to-zero/api/middleware"
)

func main() {
	// Set Gin mode based on environment
	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Initialize Kubernetes client
	k8sClient, err := k8s.NewClient()
	if err != nil {
		log.Printf("Warning: Failed to initialize Kubernetes client: %v", err)
		// Continue without Kubernetes client for development
	}

	// Create Gin router
	router := gin.New()

	// Add middleware
	router.Use(middleware.RequestIDMiddleware())
	router.Use(middleware.StructuredLogger())
	router.Use(gin.Recovery())

	// Initialize auth config
	authConfig := middleware.NewAuthConfig()
	router.Use(middleware.APIKeyAuth(authConfig))

	// Initialize handlers
	healthHandler := handlers.NewHealthHandler(k8sClient)
	deploymentHandler := handlers.NewDeploymentHandler(k8sClient)

	// Health check endpoints (no auth required)
	router.GET("/health", healthHandler.Health)
	router.GET("/ready", healthHandler.Ready)

	// API v1 routes
	v1 := router.Group("/api/v1")
	{
		deployments := v1.Group("/deployments")
		{
			deployments.POST("/:namespace/:name/scale-to-zero", deploymentHandler.ScaleToZero)
			deployments.POST("/:namespace/:name/scale-up", deploymentHandler.ScaleUp)
			deployments.GET("/:namespace/:name/status", deploymentHandler.GetStatus)
		}
	}

	// Server configuration
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:    fmt.Sprintf(":%s", port),
		Handler: router,
	}

	// Start server in a goroutine
	go func() {
		log.Printf("Server starting on port %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	// Give outstanding requests 30 seconds to complete
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}
