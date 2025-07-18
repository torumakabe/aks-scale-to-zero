package config

import (
	"fmt"
	"os"
	"strconv"
	"sync"
)

// Config holds the application configuration
type Config struct {
	Port     string
	LogLevel string
}

var (
	instance *Config
	once     sync.Once
)

// Default configuration values
const (
	DefaultPort     = "8080"
	DefaultLogLevel = "info"
)

// GetConfig returns the singleton instance of Config
func GetConfig() *Config {
	once.Do(func() {
		instance = &Config{
			Port:     getEnv("PORT", DefaultPort),
			LogLevel: getEnv("LOG_LEVEL", DefaultLogLevel),
		}
		if err := instance.validate(); err != nil {
			panic(fmt.Sprintf("invalid configuration: %v", err))
		}
	})
	return instance
}

// getEnv reads an environment variable or returns a default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// validate checks if the configuration is valid
func (c *Config) validate() error {
	// Validate port
	if port, err := strconv.Atoi(c.Port); err != nil || port < 1 || port > 65535 {
		return fmt.Errorf("invalid port: %s", c.Port)
	}

	// Validate log level
	validLogLevels := map[string]bool{
		"debug": true,
		"info":  true,
		"warn":  true,
		"error": true,
		"fatal": true,
	}
	if !validLogLevels[c.LogLevel] {
		return fmt.Errorf("invalid log level: %s", c.LogLevel)
	}

	return nil
}

// String returns a string representation of the config
func (c *Config) String() string {
	return fmt.Sprintf("Config{Port: %s, LogLevel: %s}", c.Port, c.LogLevel)
}
