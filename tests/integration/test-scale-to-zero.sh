#!/bin/bash

# Scale to Zero Integration Test
# Tests that nodes scale down to zero when all deployments are removed

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
NODE_SCALE_UP_TIMEOUT=900      # Time for new nodes to be provisioned (up to 15 minutes)
NODE_SCALE_DOWN_TIMEOUT=1200   # Time for cluster autoscaler to remove idle nodes (up to 20 minutes)

# Initialize test suite
init_test_suite "Scale to Zero Node Test" "Tests that nodes scale down to zero when all deployments are removed"

echo -e "${CYAN}Target Deployment:${NC} $NAMESPACE/$DEPLOYMENT"
echo -e "${CYAN}Scale API Endpoint:${NC} $SCALE_API_ENDPOINT"
echo -e "${CYAN}Usage:${NC} $0 [namespace] [deployment]"
echo -e "${CYAN}Example:${NC} $0 project-b sample-app-b"
echo ""

# Helper function to get node count for specific project
get_project_node_count() {
    local project="$1"
    kubectl get nodes --no-headers -l "project=$project" 2>/dev/null | wc -l
}

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

# Check if deployment exists
echo -e "${YELLOW}[INFO]${NC} Checking if deployment exists..."
if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Deployment '$DEPLOYMENT' does not exist in namespace '$NAMESPACE'"
    echo -e "${RED}[ERROR]${NC} Please check your input parameters and try again"
    cleanup_port_forward "$LOCAL_PORT"
    exit 1
fi

# Scale up to trigger node creation
PROJECT_LABEL=$(echo "$NAMESPACE" | sed 's/project-//')

run_test "Scale up deployment to trigger node provisioning" \
    "curl -s -X POST --max-time $API_TIMEOUT -H 'Content-Type: application/json' -d '{\"replicas\": 1, \"reason\": \"node-provision-test\"}' '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/scale-up' | test_json_field - '.status' 'success'"

# Wait for deployment and nodes to be ready
echo -e "${YELLOW}[INFO]${NC} Waiting for deployment to be ready (timeout: ${NODE_SCALE_UP_TIMEOUT}s)..."
run_test "Wait for deployment to be ready" \
    "wait_for_resource 'deployment' '$DEPLOYMENT' '$NAMESPACE' '$NODE_SCALE_UP_TIMEOUT'"

# Verify nodes exist for the project
sleep 30  # Wait for node provisioning to complete
NODE_COUNT=$(get_project_node_count "$PROJECT_LABEL")

run_test "Verify nodes exist for project-$PROJECT_LABEL" \
    "[ $NODE_COUNT -gt 0 ] && echo 'Node count: $NODE_COUNT'"

# Scale to zero
run_test "Scale deployment to zero" \
    "curl -s -X POST --max-time $API_TIMEOUT -H 'Content-Type: application/json' -d '{\"reason\": \"node-scale-down-test\"}' '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT/scale-to-zero' | test_json_field - '.status' 'success'"

# Verify pods are terminated
sleep 15
run_test "Verify all pods terminated" \
    "[ \$(kubectl get pods -n '$NAMESPACE' -l app='$DEPLOYMENT' --no-headers 2>/dev/null | wc -l) -eq 0 ]"

# Wait for nodes to scale down to zero
echo -e "${YELLOW}[INFO]${NC} Waiting for nodes to scale down to zero..."
echo -e "${YELLOW}[INFO]${NC} Cluster autoscaler may take up to 10 minutes to remove idle nodes"

# Monitor node scale-down
START_TIME=$(date +%s)

while true; do
    CURRENT_NODE_COUNT=$(get_project_node_count "$PROJECT_LABEL")
    ELAPSED=$(($(date +%s) - START_TIME))

    if [ "$CURRENT_NODE_COUNT" -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Nodes scaled down to zero after ${ELAPSED}s"
        break
    elif [ $ELAPSED -gt $NODE_SCALE_DOWN_TIMEOUT ]; then
        echo -e "${RED}[TIMEOUT]${NC} Nodes did not scale to zero within ${NODE_SCALE_DOWN_TIMEOUT}s (current: $CURRENT_NODE_COUNT)"
        break
    else
        echo -e "${YELLOW}[WAITING]${NC} Current node count: $CURRENT_NODE_COUNT (elapsed: ${ELAPSED}s)"
        sleep 60
    fi
done

# Verify final state
FINAL_NODE_COUNT=$(get_project_node_count "$PROJECT_LABEL")
run_test "Verify nodes scaled down to zero" \
    "[ $FINAL_NODE_COUNT -eq 0 ] && echo 'Success: No nodes remaining for project-$PROJECT_LABEL'"

# Cleanup
cleanup_port_forward "$LOCAL_PORT"

# Print summary and exit
print_test_summary
exit $?
