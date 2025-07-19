#!/bin/bash

# GPU Triton Inference Server Integration Test
# Tests NVIDIA Triton Server functionality

# Load common test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

# Ensure no debug mode is active
set +x
set +v

# Don't exit on error - we want to run all tests
set +e

# Test configuration
NAMESPACE="project-b"
DEPLOYMENT_NAME="sample-app-b"
SERVICE_NAME="sample-app-b"
SCALE_API_NAMESPACE="scale-system"
SCALE_API_SERVICE="scale-api"

# Port configuration
SCALE_API_PORT=8080
TRITON_HTTP_PORT=8000
TRITON_GRPC_PORT=8001

API_TIMEOUT=30
MODEL_LOAD_TIMEOUT=120
NODE_SCALE_UP_TIMEOUT=900      # Time for new GPU nodes to be provisioned (up to 15 minutes)
TRITON_READY_TIMEOUT=180       # 3 minutes for Triton to be ready

# Initialize test suite
init_test_suite "GPU Triton Inference Server Test" "Tests NVIDIA Triton Server functionality"

echo -e "${CYAN}Target Deployment:${NC} $NAMESPACE/$DEPLOYMENT_NAME"
echo -e "${CYAN}Scale API Endpoint:${NC} $SCALE_API_ENDPOINT"
echo -e "${CYAN}Triton HTTP Endpoint:${NC} http://localhost:$TRITON_HTTP_PORT"
echo -e "${CYAN}Model Load Timeout:${NC} ${MODEL_LOAD_TIMEOUT}s"
echo -e "${CYAN}Node Scale Up Timeout:${NC} ${NODE_SCALE_UP_TIMEOUT}s"
echo ""

# Helper function to get GPU node count for specific project
get_project_gpu_node_count() {
    local project="$1"
    kubectl get nodes --no-headers -l "project=$project,workload=gpu" 2>/dev/null | wc -l
}

# Helper function to check GPU nodes
check_gpu_nodes() {
    local expected_count="$1"
    local project="$2"
    local actual_count
    actual_count=$(get_project_gpu_node_count "$project")

    if [ "$actual_count" -eq "$expected_count" ]; then
        echo "GPU node count matches expectation: $actual_count"
        return 0
    else
        echo "GPU node count mismatch: expected $expected_count, got $actual_count"
        return 1
    fi
}

# Helper function to check Triton server health
check_triton_health() {
    local endpoint="$1"
    [ "$(curl -s -o /dev/null -w "%{http_code}" --max-time $API_TIMEOUT "$endpoint/v2/health/ready")" = "200" ]
}

# Helper function to test model inference
test_inference() {
    local endpoint="$1"
    local model_name="resnet50"

    # Create proper test data and verify actual inference works
    # Using Python to generate correct data size and validate response
    python3 << EOF
import json
import requests
import sys

# Create dummy data for ResNet50 (1x3x224x224 = 150528 values)
data = [0.0] * 150528
payload = {
    'inputs': [{
        'name': 'data',
        'shape': [1, 3, 224, 224],
        'datatype': 'FP32',
        'data': data
    }]
}

try:
    response = requests.post('$endpoint/v2/models/$model_name/infer',
                           json=payload,
                           timeout=$API_TIMEOUT)
    if response.status_code == 200:
        result = response.json()
        # Verify we got outputs with correct shape
        if 'outputs' in result and len(result['outputs']) > 0:
            output = result['outputs'][0]
            if output['shape'] == [1, 1000]:  # ResNet50 outputs 1000 classes
                sys.exit(0)  # Success
    sys.exit(1)  # Failed
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)  # Failed
EOF
}

# Validate prerequisites
if ! validate_prerequisites; then
    echo -e "${RED}Prerequisites validation failed${NC}"
    exit 1
fi

# Additional GPU test prerequisites
if ! kubectl get nodes -l "workload=gpu" >/dev/null 2>&1; then
    skip_test "GPU node pool availability check" "No GPU nodes found in cluster - this test requires GPU-enabled AKS cluster"
    print_test_summary
    exit 0
fi

# Check if deployment is already running
echo -e "${YELLOW}[INFO]${NC} Checking deployment status..."
CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

if [ "$CURRENT_REPLICAS" -gt 0 ]; then
    echo -e "${GREEN}[INFO]${NC} Deployment is already running with $CURRENT_REPLICAS replicas. Skipping scale operations."
    # Just setup port forwarding for Scale API for later tests
    run_test "Setup port-forward to Scale API" \
        "setup_port_forward '$SCALE_API_SERVICE' '$SCALE_API_NAMESPACE' '$SCALE_API_PORT' '80'" \
        "true"
else
    echo -e "${YELLOW}[INFO]${NC} Deployment is not running. Starting scale up process..."

    # Setup port forwarding for Scale API
    run_test "Setup port-forward to Scale API" \
        "setup_port_forward '$SCALE_API_SERVICE' '$SCALE_API_NAMESPACE' '$SCALE_API_PORT' '80'" \
        "true"

    # Scale up GPU deployment
    run_test "Scale up GPU deployment" \
        "curl -s -X POST --max-time $API_TIMEOUT -H 'Content-Type: application/json' -d '{\"replicas\": 1, \"reason\": \"gpu-inference-test\"}' '$SCALE_API_ENDPOINT/api/v1/deployments/$NAMESPACE/$DEPLOYMENT_NAME/scale-up' | test_json_field - '.status' 'success'"

    # Wait for GPU deployment to be ready
    echo -e "${YELLOW}[INFO]${NC} Waiting for deployment to be ready (timeout: ${NODE_SCALE_UP_TIMEOUT}s)..."
    run_test "Wait for GPU deployment to be ready" \
        "wait_for_resource 'deployment' '$DEPLOYMENT_NAME' '$NAMESPACE' '$NODE_SCALE_UP_TIMEOUT'"
fi

# Verify GPU pod is running
run_test "Verify GPU pod is running" \
    "kubectl get pods -n '$NAMESPACE' -l app='$DEPLOYMENT_NAME' -o wide | grep -q 'Running'"

# Setup port forwarding to Triton server (not a test)
echo -e "${YELLOW}[INFO]${NC} Setting up port-forward to Triton server..."
kubectl port-forward "svc/$SERVICE_NAME" "$TRITON_HTTP_PORT:8000" "$TRITON_GRPC_PORT:8001" -n "$NAMESPACE" >/dev/null 2>&1 &
TRITON_PF_PID=$!

# Wait for port-forward to establish
sleep 5

# Wait for Triton server to be ready with retry logic
echo -e "${YELLOW}[INFO]${NC} Waiting for Triton server to be ready (timeout: ${TRITON_READY_TIMEOUT}s)..."
START_TIME=$(date +%s)
while true; do
    if [ "$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:$TRITON_HTTP_PORT/v2/health/ready" 2>/dev/null)" = "200" ]; then
        echo -e "${GREEN}[INFO]${NC} Triton server is ready"
        break
    fi

    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -gt $TRITON_READY_TIMEOUT ]; then
        echo -e "${RED}[ERROR]${NC} Triton server failed to become ready within ${TRITON_READY_TIMEOUT}s"
        kill $TRITON_PF_PID 2>/dev/null || true
        cleanup_port_forward "$SCALE_API_PORT"
        print_test_summary
        exit 1
    fi

    echo -e "${YELLOW}[INFO]${NC} Waiting for Triton... ($ELAPSED/${TRITON_READY_TIMEOUT}s)"
    sleep 10
done

# Check Triton server health endpoint (should pass since we already verified)
run_test "Check Triton server health endpoint" \
    "check_triton_health 'http://localhost:$TRITON_HTTP_PORT'"

# Verify ResNet50 model is loaded
run_test "Verify ResNet50 model is loaded" \
    "[ \"\$(curl -s -o /dev/null -w \"%{http_code}\" --max-time $API_TIMEOUT 'http://localhost:$TRITON_HTTP_PORT/v2/models/resnet50/ready')\" = \"200\" ]"

# Test inference functionality
run_test "Test ResNet50 inference functionality" \
    "test_inference 'http://localhost:$TRITON_HTTP_PORT'"

# End of inference tests

# Kill Triton port-forward if still running
if [ -n "$TRITON_PF_PID" ]; then
    kill $TRITON_PF_PID 2>/dev/null || true
fi

# Cleanup
cleanup_port_forward "$SCALE_API_PORT"
kill $TRITON_PF_PID 2>/dev/null || true


# Print summary and exit
print_test_summary
exit $?
