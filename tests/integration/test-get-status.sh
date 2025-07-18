#!/bin/bash

# Deployment Status API Integration Test
# Tests the deployment status endpoint functionality and response validation

# Load common test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

# Ensure no debug mode is active
set +x
set +v

# Don't exit on error - we want to run all tests
set +e

# Default values
DEFAULT_NAMESPACE="project-a"
DEFAULT_DEPLOYMENT="sample-app-a"

# Parse command line arguments
NAMESPACE="${1:-$DEFAULT_NAMESPACE}"
DEPLOYMENT="${2:-$DEFAULT_DEPLOYMENT}"

# Test configuration
LOCAL_PORT=8080
SCALE_API_NAMESPACE="scale-system"
SCALE_API_SERVICE="scale-api"
API_TIMEOUT=30
RESPONSE_TIME_LIMIT=2

# Initialize test suite
init_test_suite "Deployment Status API Test" "Tests deployment status endpoint functionality and response validation"

echo -e "${CYAN}Target Deployment:${NC} $NAMESPACE/$DEPLOYMENT"
echo -e "${CYAN}Scale API Endpoint:${NC} $SCALE_API_ENDPOINT"
echo -e "${CYAN}Usage:${NC} $0 [namespace] [deployment]"
echo -e "${CYAN}Example:${NC} $0 project-b sample-app-b"
echo ""

# Helper function to test response time
test_response_time() {
    local url="$1"
    local max_time="$2"

    local start_time end_time duration
    start_time=$(date +%s%3N)

    if curl -s --max-time "$API_TIMEOUT" "$url" >/dev/null 2>&1; then
        end_time=$(date +%s%3N)
        duration=$((end_time - start_time))

        if [ $duration -le $((max_time * 1000)) ]; then
            echo "Response time: ${duration}ms (within ${max_time}s limit)"
            return 0
        else
            echo "Response time: ${duration}ms (exceeds ${max_time}s limit)"
            return 1
        fi
    else
        echo "Request failed"
        return 1
    fi
}

# Validate prerequisites
if ! validate_prerequisites; then
    echo -e "${RED}Prerequisites validation failed${NC}"
    exit 1
fi

# Setup port forwarding
run_test "Setup port-forward to Scale API" \
    "setup_port_forward '$SCALE_API_SERVICE' '$SCALE_API_NAMESPACE' '$LOCAL_PORT' '80'" \
    "true"

# Health endpoint check
run_test "Health endpoint check" \
    "test_http_endpoint '$SCALE_API_ENDPOINT/health' '200'"

# Ready endpoint check
run_test "Ready endpoint check" \
    "test_http_endpoint '$SCALE_API_ENDPOINT/ready' '200'"

# Basic status endpoint functionality
run_test "Basic status endpoint functionality" \
    "test_http_endpoint '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/status' '200'"

# Status response structure validation
STATUS_RESPONSE=$(curl -s --max-time $API_TIMEOUT "$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/status")

run_test "Status response contains deployment.name field" \
    "test_json_field \"\$STATUS_RESPONSE\" '.deployment.name' '$DEPLOYMENT'"

run_test "Status response contains deployment.namespace field" \
    "test_json_field \"\$STATUS_RESPONSE\" '.deployment.namespace' '$NAMESPACE'"

run_test "Status response contains deployment object" \
    "test_json_field \"\$STATUS_RESPONSE\" '.deployment'"

run_test "Status response contains deployment.desired_replicas field" \
    "test_json_field \"\$STATUS_RESPONSE\" '.deployment.desired_replicas'"

run_test "Status response contains deployment.current_replicas field" \
    "test_json_field \"\$STATUS_RESPONSE\" '.deployment.current_replicas'"

# Data accuracy validation
DESIRED_REPLICAS=$(echo "$STATUS_RESPONSE" | jq -r '.deployment.desired_replicas // 0')
CURRENT_REPLICAS=$(echo "$STATUS_RESPONSE" | jq -r '.deployment.current_replicas // 0')

run_test "Validate numeric replica values" \
    "[ '$DESIRED_REPLICAS' -ge 0 ] && [ '$CURRENT_REPLICAS' -ge 0 ]"

# Error handling - Non-existent deployment
run_test "Error handling - Non-existent deployment" \
    "test_http_endpoint '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/non-existent-deployment/status' '404'"

# Error handling - Non-existent namespace
run_test "Error handling - Non-existent namespace" \
    "test_http_endpoint '$SCALE_API_ENDPOINT/api/v1/deployments/non-existent-namespace/$DEPLOYMENT/status' '404'"

# Response time performance test
run_test "Response time performance test (< ${RESPONSE_TIME_LIMIT}s)" \
    "test_response_time '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/status' '$RESPONSE_TIME_LIMIT'"

# Multiple consecutive requests stability
run_test "Multiple consecutive requests stability" \
    "for i in {1..5}; do test_http_endpoint '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/status' '200' || exit 1; done"

# JSON response format validation
run_test "JSON response format validation" \
    "curl -s --max-time $API_TIMEOUT '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/status' | jq empty"

# Cleanup
cleanup_port_forward "$LOCAL_PORT"

# Print summary and exit
print_test_summary
exit $?
