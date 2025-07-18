#!/bin/bash

# Common Test Framework for Integration Tests
# Provides unified test execution and output formatting

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color

# Test tracking variables
export TESTS_TOTAL=0
export TESTS_PASSED=0
export TESTS_FAILED=0
export TESTS_SKIPPED=0

# Test configuration
export SCALE_API_ENDPOINT="http://localhost:8080"
export CURL_TIMEOUT=10

# Initialize test suite
init_test_suite() {
    local suite_name="$1"
    local description="$2"

    echo -e "${BLUE}================================================================${NC}"
    echo -e "${WHITE}  $suite_name${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${CYAN}Description: $description${NC}"
    echo -e "${CYAN}Timestamp: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""

    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
}

# Run a test with standardized output
run_test() {
    local test_name="$1"
    local test_command="$2"
    local is_critical="${3:-false}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    echo -e "${YELLOW}[TEST $TESTS_TOTAL]${NC} $test_name"
    echo -e "${PURPLE}Command:${NC} $test_command"

    # Execute the test command
    local start_time
    start_time=$(date +%s)
    local exit_status=0

    if eval "$test_command" 2>&1; then
        exit_status=0
    else
        exit_status=$?
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Report result
    if [ "$exit_status" -eq 0 ]; then
        echo -e "${GREEN}✓ PASSED${NC} (${duration}s)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAILED${NC} (${duration}s) - Exit code: $exit_status"
        TESTS_FAILED=$((TESTS_FAILED + 1))

        if [ "$is_critical" = "true" ]; then
            echo -e "${RED}CRITICAL TEST FAILED - Stopping test suite${NC}"
            print_test_summary
            exit 1
        fi
    fi

    echo ""
    return $exit_status
}

# Skip a test with reason
skip_test() {
    local test_name="$1"
    local reason="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))

    echo -e "${YELLOW}[TEST $TESTS_TOTAL]${NC} $test_name"
    echo -e "${CYAN}⊘ SKIPPED${NC} - $reason"
    echo ""
}

# Print final test summary
print_test_summary() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${WHITE}  TEST SUMMARY${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${WHITE}Total Tests:${NC}  $TESTS_TOTAL"
    echo -e "${GREEN}Passed:${NC}       $TESTS_PASSED"
    echo -e "${RED}Failed:${NC}       $TESTS_FAILED"
    echo -e "${CYAN}Skipped:${NC}      $TESTS_SKIPPED"

    # Calculate success rate
    if [ "$TESTS_TOTAL" -gt 0 ]; then
        local success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
        echo -e "${WHITE}Success Rate:${NC} ${success_rate}%"
    fi

    echo -e "${CYAN}Completed:${NC}    $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}================================================================${NC}"

    # Return exit code based on results
    if [ "$TESTS_FAILED" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate required tools
validate_prerequisites() {
    local required_tools=("curl" "jq" "kubectl")
    local missing_tools=()

    echo -e "${YELLOW}[PREREQ]${NC} Validating required tools..."

    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}✗ Missing required tools: ${missing_tools[*]}${NC}"
        return 1
    else
        echo -e "${GREEN}✓ All required tools available${NC}"
        return 0
    fi
}

# Test HTTP endpoint
test_http_endpoint() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-$CURL_TIMEOUT}"

    local response
    local http_status

    response=$(curl -s -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null)
    http_status="${response: -3}"

    if [ "$http_status" = "$expected_status" ]; then
        return 0
    else
        echo "Expected HTTP $expected_status, got $http_status"
        return 1
    fi
}

# Test JSON response structure
test_json_field() {
    local json_response="$1"
    local field_path="$2"
    local expected_value="$3"

    # Handle pipe input
    if [ "$json_response" = "-" ]; then
        json_response=$(cat)
    fi

    if ! echo "$json_response" | jq -e . >/dev/null 2>&1; then
        echo "Invalid JSON response"
        return 1
    fi

    if [ -n "$expected_value" ]; then
        local actual_value
        actual_value=$(echo "$json_response" | jq -r "$field_path" 2>/dev/null)
        if [ "$actual_value" = "$expected_value" ]; then
            return 0
        else
            echo "Expected '$expected_value', got '$actual_value'"
            return 1
        fi
    else
        if echo "$json_response" | jq -e "$field_path" >/dev/null 2>&1; then
            return 0
        else
            echo "Field '$field_path' not found"
            return 1
        fi
    fi
}

# Wait for kubernetes resource to be ready
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local timeout="${4:-300}"

    echo "Waiting for $resource_type/$resource_name in namespace $namespace..."
    
    if [ "$resource_type" = "deployment" ]; then
        # For deployments, use rollout status which properly waits for replicas to be ready
        kubectl rollout status "$resource_type/$resource_name" \
            -n "$namespace" --timeout="${timeout}s" >/dev/null 2>&1
    else
        # For other resources, use the standard wait command
        kubectl wait --for=condition=ready "$resource_type/$resource_name" \
            -n "$namespace" --timeout="${timeout}s" >/dev/null 2>&1
    fi
}

# Setup port forwarding with retry
setup_port_forward() {
    local service="$1"
    local namespace="$2"
    local local_port="$3"
    local remote_port="$4"
    local timeout="${5:-30}"

    echo "Setting up port-forward: localhost:$local_port -> $service:$remote_port (namespace: $namespace)"

    # Kill existing port-forward if any
    pkill -f "kubectl.*port-forward.*$local_port" 2>/dev/null || true
    sleep 2

    # Start new port-forward in background
    kubectl port-forward "svc/$service" "$local_port:$remote_port" -n "$namespace" >/dev/null 2>&1 &
    local pf_pid=$!

    # Wait for port-forward to be ready
    local count=0
    while [ $count -lt $timeout ]; do
        if curl -s "http://localhost:$local_port/health" >/dev/null 2>&1; then
            echo "Port-forward ready (PID: $pf_pid)"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done

    echo "Port-forward setup failed after ${timeout}s"
    kill $pf_pid 2>/dev/null || true
    return 1
}

# Cleanup port forwarding
cleanup_port_forward() {
    local local_port="$1"

    echo "Cleaning up port-forward on port $local_port..."
    pkill -f "kubectl.*port-forward.*$local_port" 2>/dev/null || true
    sleep 2
}
