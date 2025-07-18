#!/bin/bash

# Scale API Integration Test
# Tests Scale API functionality focusing on replica count changes through the API

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
SCALE_WAIT_TIME=10

# Initialize test suite
init_test_suite "Scale API Integration Test" "Tests Scale API endpoints and replica count changes"

echo -e "${CYAN}Target Deployment:${NC} $NAMESPACE/$DEPLOYMENT"
echo -e "${CYAN}Scale API Endpoint:${NC} $SCALE_API_ENDPOINT"
echo -e "${CYAN}Usage:${NC} $0 [namespace] [deployment]"
echo -e "${CYAN}Example:${NC} $0 project-b sample-app-b"
echo ""

# Helper function to get deployment replica count
get_replica_count() {
    local namespace="$1"
    local deployment="$2"
    kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
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

# Health endpoint
run_test "Health endpoint check" \
    "test_http_endpoint '$SCALE_API_ENDPOINT/health' '200'"

# Ready endpoint
run_test "Ready endpoint check" \
    "test_http_endpoint '$SCALE_API_ENDPOINT/ready' '200'"

# Get deployment status
run_test "Get deployment status" \
    "curl -s --max-time $API_TIMEOUT '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/status' | test_json_field - '.deployment.name' '$DEPLOYMENT'"

# Scale to specific replica counts
run_test "Scale deployment to 3 replicas" \
    "curl -s -X POST --max-time $API_TIMEOUT -H 'Content-Type: application/json' -d '{\"replicas\": 3, \"reason\": \"api-test-scale-up\"}' '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/scale-up' | test_json_field - '.status' 'success'"

# Wait for scale operation to complete
sleep $SCALE_WAIT_TIME

# Verify scale up via API status endpoint
run_test "Verify scale up via API status" \
    "curl -s --max-time $API_TIMEOUT '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/status' | test_json_field - '.deployment.current_replicas' '3'"

# Verify actual deployment replicas
run_test "Verify actual deployment has 3 replicas" \
    "[ \$(get_replica_count '$NAMESPACE' '$DEPLOYMENT') -eq 3 ]"

# Scale down to 2 replicas
run_test "Scale down deployment to 2 replicas" \
    "curl -s -X POST --max-time $API_TIMEOUT -H 'Content-Type: application/json' -d '{\"replicas\": 2, \"reason\": \"api-test-scale-down\"}' '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/scale-up' | test_json_field - '.status' 'success'"

# Wait for scale operation to complete
sleep $SCALE_WAIT_TIME

# Verify scale down
run_test "Verify scale down to 2 replicas" \
    "[ \$(get_replica_count '$NAMESPACE' '$DEPLOYMENT') -eq 2 ]"

# Test scale-to-zero endpoint
run_test "Scale to zero via API" \
    "curl -s -X POST --max-time $API_TIMEOUT -H 'Content-Type: application/json' -d '{\"reason\": \"api-test-scale-to-zero\"}' '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/scale-to-zero' | test_json_field - '.status' 'success'"

# Wait for scale operation to complete
sleep $SCALE_WAIT_TIME

# Verify scale to zero
run_test "Verify deployment scaled to zero" \
    "[ \$(get_replica_count '$NAMESPACE' '$DEPLOYMENT') -eq 0 ]"

# Scale back up from zero
run_test "Scale up from zero to 1 replica" \
    "curl -s -X POST --max-time $API_TIMEOUT -H 'Content-Type: application/json' -d '{\"replicas\": 1, \"reason\": \"api-test-recovery\"}' '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/scale-up' | test_json_field - '.status' 'success'"

# Wait for scale operation to complete
sleep $SCALE_WAIT_TIME

# Verify recovery from zero
run_test "Verify recovery from zero" \
    "[ \$(get_replica_count '$NAMESPACE' '$DEPLOYMENT') -eq 1 ]"

# Cleanup
cleanup_port_forward "$LOCAL_PORT"

# Print summary and exit
print_test_summary
exit $?
