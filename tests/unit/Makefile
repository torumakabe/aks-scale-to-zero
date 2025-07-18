# Makefile for running unit tests

# Variables
API_DIR := ../../src/api
COVERAGE_DIR := ./coverage
COVERAGE_FILE := $(COVERAGE_DIR)/coverage.out
COVERAGE_HTML := $(COVERAGE_DIR)/coverage.html
GO_TEST_FLAGS := -v -race -timeout=30s

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: all test coverage coverage-html clean install-deps lint pre-test help

# Default target
all: test

# Help target
help:
	@echo "$(GREEN)AKS Scale to Zero - Unit Test Runner$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(YELLOW)make test$(NC)          - Run all unit tests"
	@echo "  $(YELLOW)make coverage$(NC)      - Run tests with coverage report"
	@echo "  $(YELLOW)make coverage-html$(NC) - Generate HTML coverage report"
	@echo "  $(YELLOW)make lint$(NC)          - Run linters (golangci-lint)"
	@echo "  $(YELLOW)make clean$(NC)         - Clean test artifacts"
	@echo "  $(YELLOW)make install-deps$(NC)  - Install test dependencies"
	@echo "  $(YELLOW)make watch$(NC)         - Run tests in watch mode"
	@echo ""
	@echo "Test specific packages:"
	@echo "  $(YELLOW)make test-handlers$(NC)  - Test handlers package only"
	@echo "  $(YELLOW)make test-k8s$(NC)       - Test k8s package only"
	@echo "  $(YELLOW)make test-middleware$(NC)- Test middleware package only"
	@echo ""

# Install test dependencies
install-deps:
	@echo "$(GREEN)Installing test dependencies...$(NC)"
	cd $(API_DIR) && go mod download
	@echo "$(GREEN)Installing test tools...$(NC)"
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install github.com/onsi/ginkgo/v2/ginkgo@latest
	go install gotest.tools/gotestsum@latest

# Run all unit tests
test: pre-test
	@echo "$(GREEN)Running all unit tests...$(NC)"
	@cd $(API_DIR) && go test ./... $(GO_TEST_FLAGS) \
		-tags=unit \
		-skip="Integration|E2E" || (echo "$(RED)Tests failed!$(NC)" && exit 1)
	@echo "$(GREEN)All tests passed!$(NC)"

# Run tests with coverage
coverage: pre-test
	@echo "$(GREEN)Running tests with coverage...$(NC)"
	@mkdir -p $(COVERAGE_DIR)
	@cd $(API_DIR) && go test ./... $(GO_TEST_FLAGS) \
		-tags=unit \
		-skip="Integration|E2E" \
		-coverprofile=$(abspath $(COVERAGE_FILE)) \
		-covermode=atomic
	@echo "$(GREEN)Coverage report generated at: $(COVERAGE_FILE)$(NC)"
	@cd $(API_DIR) && go tool cover -func=$(abspath $(COVERAGE_FILE)) | grep total | awk '{print "Total coverage: " $$3}'

# Generate HTML coverage report
coverage-html: coverage
	@echo "$(GREEN)Generating HTML coverage report...$(NC)"
	@cd $(API_DIR) && go tool cover -html=$(abspath $(COVERAGE_FILE)) -o=$(abspath $(COVERAGE_HTML))
	@echo "$(GREEN)HTML coverage report generated at: $(COVERAGE_HTML)$(NC)"
	@echo "Opening coverage report in browser..."
	@command -v xdg-open >/dev/null 2>&1 && xdg-open $(COVERAGE_HTML) || \
		command -v open >/dev/null 2>&1 && open $(COVERAGE_HTML) || \
		echo "Please open $(COVERAGE_HTML) in your browser"

# Test specific packages
test-handlers: pre-test
	@echo "$(GREEN)Testing handlers package...$(NC)"
	@cd $(API_DIR) && go test ./handlers/... $(GO_TEST_FLAGS) -tags=unit

test-k8s: pre-test
	@echo "$(GREEN)Testing k8s package...$(NC)"
	@cd $(API_DIR) && go test ./k8s/... $(GO_TEST_FLAGS) -tags=unit

test-middleware: pre-test
	@echo "$(GREEN)Testing middleware package...$(NC)"
	@cd $(API_DIR) && go test ./middleware/... $(GO_TEST_FLAGS) -tags=unit

test-config: pre-test
	@echo "$(GREEN)Testing config package...$(NC)"
	@cd $(API_DIR) && go test ./config/... $(GO_TEST_FLAGS) -tags=unit

test-utils: pre-test
	@echo "$(GREEN)Testing utils package...$(NC)"
	@cd $(API_DIR) && go test ./utils/... $(GO_TEST_FLAGS) -tags=unit

# Run tests in watch mode
watch:
	@echo "$(GREEN)Running tests in watch mode...$(NC)"
	@echo "$(YELLOW)Watching for changes in $(API_DIR)...$(NC)"
	@command -v gotestsum >/dev/null 2>&1 || (echo "$(RED)gotestsum not installed. Run 'make install-deps' first$(NC)" && exit 1)
	@cd $(API_DIR) && gotestsum --watch -- -tags=unit -skip="Integration|E2E" $(GO_TEST_FLAGS)

# Run tests with verbose output and specific test filter
test-verbose:
	@echo "$(GREEN)Running tests with verbose output...$(NC)"
	@cd $(API_DIR) && go test ./... -v -tags=unit -skip="Integration|E2E"

# Run specific test by name
test-run:
	@if [ -z "$(TEST)" ]; then \
		echo "$(RED)Please specify TEST variable. Example: make test-run TEST=TestScaleToZero$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Running test: $(TEST)$(NC)"
	@cd $(API_DIR) && go test ./... -v -tags=unit -run="$(TEST)"

# Run benchmarks
bench:
	@echo "$(GREEN)Running benchmarks...$(NC)"
	@cd $(API_DIR) && go test ./... -bench=. -benchmem -tags=unit -run=^$$

# Lint code
lint: pre-test
	@echo "$(GREEN)Running linters...$(NC)"
	@cd $(API_DIR) && golangci-lint run ./... --timeout=10m || (echo "$(RED)Linting failed!$(NC)" && exit 1)
	@echo "$(GREEN)Linting passed!$(NC)"

# Run go vet
vet:
	@echo "$(GREEN)Running go vet...$(NC)"
	@cd $(API_DIR) && go vet ./...

# Check for missing test files
check-coverage:
	@echo "$(GREEN)Checking test coverage for all packages...$(NC)"
	@cd $(API_DIR) && \
	for pkg in $$(go list ./... | grep -v /vendor/); do \
		files=$$(go list -f '{{range .GoFiles}}{{$$.Dir}}/{{.}} {{end}}' $$pkg); \
		if [ -n "$$files" ]; then \
			testfiles=$$(go list -f '{{range .TestGoFiles}}{{$$.Dir}}/{{.}} {{end}}' $$pkg); \
			if [ -z "$$testfiles" ]; then \
				echo "$(YELLOW)Warning: No tests for package $$pkg$(NC)"; \
			fi \
		fi \
	done

# Pre-test checks
pre-test:
	@echo "$(GREEN)Running pre-test checks...$(NC)"
	@cd $(API_DIR) && go mod verify
	@cd $(API_DIR) && go fmt ./...

# Clean test artifacts
clean:
	@echo "$(GREEN)Cleaning test artifacts...$(NC)"
	@rm -rf $(COVERAGE_DIR)
	@cd $(API_DIR) && go clean -testcache
	@echo "$(GREEN)Clean complete!$(NC)"

# CI mode - runs all checks and tests
ci: lint vet test coverage
	@echo "$(GREEN)CI checks complete!$(NC)"

# Quick test - runs only fast tests
quick:
	@echo "$(GREEN)Running quick tests (no race detector)...$(NC)"
	@cd $(API_DIR) && go test ./... -tags=unit -skip="Integration|E2E" -short

# Generate test report in JUnit format (for CI integration)
test-junit: pre-test
	@echo "$(GREEN)Running tests with JUnit output...$(NC)"
	@mkdir -p $(COVERAGE_DIR)
	@cd $(API_DIR) && \
		command -v gotestsum >/dev/null 2>&1 || go install gotest.tools/gotestsum@latest && \
		gotestsum --junitfile=$(abspath $(COVERAGE_DIR)/junit.xml) -- \
		./... -tags=unit -skip="Integration|E2E" $(GO_TEST_FLAGS)

# Test with different Go versions (requires Docker)
test-versions:
	@echo "$(GREEN)Testing with multiple Go versions...$(NC)"
	@for version in 1.22 1.23 1.24; do \
		echo "$(YELLOW)Testing with Go $$version...$(NC)"; \
		docker run --rm -v $(shell cd $(API_DIR) && pwd):/app -w /app golang:$$version \
			go test ./... -tags=unit -skip="Integration|E2E"; \
	done

# Debug mode - runs tests with delve debugger support
debug:
	@echo "$(GREEN)Running tests in debug mode...$(NC)"
	@echo "$(YELLOW)You can now attach a debugger to the test process$(NC)"
	@cd $(API_DIR) && dlv test ./handlers -- -test.v -test.run="$(TEST)"

# Summary of test results
summary: coverage
	@echo ""
	@echo "$(GREEN)========== Test Summary ==========$(NC)"
	@cd $(API_DIR) && go tool cover -func=$(abspath $(COVERAGE_FILE)) | tail -5
	@echo "$(GREEN)=================================$(NC)"