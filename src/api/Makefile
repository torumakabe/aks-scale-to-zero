.PHONY: help build test test-unit test-integration run clean lint

# Go parameters
GOCMD=/usr/local/go/bin/go
GOBUILD=$(GOCMD) build
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod
BINARY_NAME=scale-api

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build: ## Build the binary
	$(GOBUILD) -o $(BINARY_NAME) -v .

test: test-unit test-integration ## Run all tests

test-unit: ## Run unit tests
	$(GOTEST) -v ./models ./config ./utils ./middleware

test-integration: ## Run integration tests
	$(GOTEST) -v ./handlers ./k8s -tags=integration

test-coverage: ## Run tests with coverage
	$(GOTEST) -v -coverprofile=coverage.out ./...
	$(GOCMD) tool cover -html=coverage.out -o coverage.html

run: ## Run the application
	$(GOCMD) run main.go

run-dev: ## Run with development settings
	GIN_MODE=debug LOG_LEVEL=debug $(GOCMD) run main.go

run-auth: ## Run with auth enabled
	API_KEY=test-key $(GOCMD) run main.go

clean: ## Clean build artifacts
	$(GOCMD) clean
	rm -f $(BINARY_NAME)
	rm -f coverage.out coverage.html

deps: ## Download dependencies
	$(GOMOD) download

tidy: ## Tidy and verify dependencies
	$(GOMOD) tidy
	$(GOMOD) verify

lint: ## Run linter
	golangci-lint run --timeout=5m

fmt: ## Format code
	$(GOCMD) fmt ./...

vet: ## Run go vet
	$(GOCMD) vet ./...

# Development helpers
.PHONY: test-health test-api-auth test-logging

test-health: ## Test health endpoint
	@echo "Testing health endpoint..."
	@curl -s http://localhost:8080/health | jq .

test-api-auth: ## Test API with authentication
	@echo "Testing API with authentication..."
	@echo "Without auth (should fail):"
	@curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/v1/deployments/default/test/status
	@echo "With auth (should work):"
	@curl -s -H "Authorization: Bearer test-key" http://localhost:8080/api/v1/deployments/default/test/status | jq .

test-logging: ## Test logging output
	@echo "Making request to test logging..."
	@curl -s http://localhost:8080/health > /dev/null
	@echo "Check server logs for structured JSON output"