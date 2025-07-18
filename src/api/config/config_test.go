package config

import (
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGetConfig_DefaultValues(t *testing.T) {
	config := GetConfig()

	port, err := strconv.Atoi(config.Port)
	assert.NoError(t, err)
	assert.Greater(t, port, 0)
	assert.LessOrEqual(t, port, 65535)

	validLogLevels := []string{"debug", "info", "warn", "error", "fatal"}
	assert.Contains(t, validLogLevels, config.LogLevel)
}

func TestGetConfig_Singleton(t *testing.T) {
	config1 := GetConfig()
	config2 := GetConfig()
	assert.Equal(t, config1, config2)
}

func TestConfig_String(t *testing.T) {
	config := GetConfig()
	str := config.String()
	assert.Contains(t, str, "Config{")
	assert.Contains(t, str, "Port:")
	assert.Contains(t, str, "LogLevel:")
}
