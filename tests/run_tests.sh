#!/bin/bash

# Trust Store Manager Test Runner
# Runs all tests for both Bash and Go implementations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo -e "${BLUE}=== Trust Store Manager Test Suite ===${NC}"
echo "Project root: $PROJECT_ROOT"
echo

# Function to run test suite
run_test_suite() {
    local suite_name="$1"
    local test_command="$2"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    echo -e "${BLUE}Running: $suite_name${NC}"
    echo "Command: $test_command"
    
    if eval "$test_command" > "/tmp/test_suite_$$.log" 2>&1; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo -e "${GREEN}✓ PASSED: $suite_name${NC}"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo -e "${RED}✗ FAILED: $suite_name${NC}"
        echo "Error output:"
        cat "/tmp/test_suite_$$.log" | head -20 | sed 's/^/  /'
    fi
    echo
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # Check Go
    if command -v go >/dev/null 2>&1; then
        echo "✓ Go: $(go version)"
    else
        echo -e "${YELLOW}⚠ Go not found - Go tests will be skipped${NC}"
    fi
    
    # Check Java/JRE
    if command -v java >/dev/null 2>&1 && command -v keytool >/dev/null 2>&1; then
        echo "✓ Java/JRE: $(java -version 2>&1 | head -1)"
    else
        echo -e "${YELLOW}⚠ Java/JRE not found - JKS/PKCS12 tests will be limited${NC}"
    fi
    
    # Check OpenSSL
    if command -v openssl >/dev/null 2>&1; then
        echo "✓ OpenSSL: $(openssl version)"
    else
        echo -e "${RED}✗ OpenSSL not found - some tests will fail${NC}"
    fi
    
    echo
}

# Create test fixtures
setup_test_fixtures() {
    echo -e "${BLUE}Setting up test fixtures...${NC}"
    
    if [[ -x "$SCRIPT_DIR/fixtures/create_test_keystores.sh" ]]; then
        "$SCRIPT_DIR/fixtures/create_test_keystores.sh" || true
    else
        echo -e "${YELLOW}⚠ Test fixture script not found or not executable${NC}"
    fi
    echo
}

# Test bash implementation
test_bash_implementation() {
    echo -e "${BLUE}=== Testing Bash Implementation ===${NC}"
    
    # Test basic functionality
    run_test_suite "Bash - Help Display" \
        "cd '$PROJECT_ROOT' && ./bash-trust-store-manager/trust-store-manager-enterprise.sh --help"
    
    # Test noop requirement
    run_test_suite "Bash - Noop Requirement" \
        "cd '$PROJECT_ROOT' && ! ./bash-trust-store-manager/trust-store-manager-enterprise.sh --auto -d /tmp"
    
    # Test noop mode
    run_test_suite "Bash - Noop Mode" \
        "cd '$PROJECT_ROOT' && ./bash-trust-store-manager/trust-store-manager-enterprise.sh --noop --auto -d /tmp"
    
    # Test configuration loading
    run_test_suite "Bash - Config Loading" \
        "cd '$PROJECT_ROOT' && ./bash-trust-store-manager/trust-store-manager-enterprise.sh --noop --config config.yaml --auto -d /tmp"
    
    # Run unit tests if available
    if [[ -x "$SCRIPT_DIR/unit/test_trust_store_operations.sh" ]]; then
        run_test_suite "Bash - Unit Tests" \
            "cd '$PROJECT_ROOT' && '$SCRIPT_DIR/unit/test_trust_store_operations.sh'"
    fi
}

# Test Go implementation
test_go_implementation() {
    if ! command -v go >/dev/null 2>&1; then
        echo -e "${YELLOW}Skipping Go tests - Go not available${NC}"
        return
    fi
    
    echo -e "${BLUE}=== Testing Go Implementation ===${NC}"
    
    # Test basic functionality
    run_test_suite "Go - Help Display" \
        "cd '$PROJECT_ROOT/go-trust-store-manager' && go run . --help"
    
    # Test noop requirement
    run_test_suite "Go - Noop Requirement" \
        "cd '$PROJECT_ROOT/go-trust-store-manager' && ! go run . --auto -d /tmp"
    
    # Test noop mode with JRE detection
    run_test_suite "Go - Noop Mode with JRE Detection" \
        "cd '$PROJECT_ROOT/go-trust-store-manager' && go run . --noop --auto -d /tmp"
    
    # Test configuration loading
    run_test_suite "Go - Config Loading" \
        "cd '$PROJECT_ROOT/go-trust-store-manager' && go run . --noop --config ../config.yaml --auto -d /tmp"
    
    # Test Go unit tests
    run_test_suite "Go - Unit Tests" \
        "cd '$SCRIPT_DIR/unit' && go test -v"
    
    # Test Go benchmarks
    run_test_suite "Go - Benchmarks" \
        "cd '$SCRIPT_DIR/unit' && go test -bench=. -benchtime=1s"
}

# Test command equivalence
test_command_equivalence() {
    echo -e "${BLUE}=== Testing Command Equivalence ===${NC}"
    
    # Test that both implementations support the same core flags
    local flags=(--noop --help -d -c -b --auto --config)
    
    for flag in "${flags[@]}"; do
        # Test bash help contains flag
        if ./bash-trust-store-manager/trust-store-manager-enterprise.sh --help | grep -q "$flag"; then
            bash_has_flag=true
        else
            bash_has_flag=false
        fi
        
        # Test Go help contains flag (if Go is available)
        if command -v go >/dev/null 2>&1; then
            if cd go-trust-store-manager && go run . --help | grep -q "$flag"; then
                go_has_flag=true
            else
                go_has_flag=false
            fi
            cd "$PROJECT_ROOT"
        else
            go_has_flag=true  # Skip check if Go not available
        fi
        
        if [[ "$bash_has_flag" == "true" && "$go_has_flag" == "true" ]]; then
            echo -e "${GREEN}✓ Flag equivalence: $flag${NC}"
        else
            echo -e "${RED}✗ Flag equivalence: $flag (Bash: $bash_has_flag, Go: $go_has_flag)${NC}"
            FAILED_SUITES=$((FAILED_SUITES + 1))
        fi
        TOTAL_SUITES=$((TOTAL_SUITES + 1))
    done
}

# Test performance
test_performance() {
    echo -e "${BLUE}=== Performance Tests ===${NC}"
    
    # Create a temporary directory with some files for testing
    local test_dir="/tmp/trust-store-perf-test-$$"
    mkdir -p "$test_dir"
    
    # Create some dummy files
    for i in {1..10}; do
        echo "test content $i" > "$test_dir/file$i.txt"
    done
    
    # Test bash performance
    run_test_suite "Bash - Performance Test" \
        "cd '$PROJECT_ROOT' && timeout 30s ./bash-trust-store-manager/trust-store-manager-enterprise.sh --noop --auto -d '$test_dir'"
    
    # Test Go performance  
    if command -v go >/dev/null 2>&1; then
        run_test_suite "Go - Performance Test" \
            "cd '$PROJECT_ROOT/go-trust-store-manager' && timeout 30s go run . --noop --auto -d '$test_dir'"
    fi
    
    # Cleanup
    rm -rf "$test_dir"
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    echo "Starting comprehensive test suite..."
    echo "$(date)"
    echo
    
    # Run test phases
    check_prerequisites
    setup_test_fixtures
    test_bash_implementation
    test_go_implementation
    test_command_equivalence
    test_performance
    
    # Print summary
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Total test suites: $TOTAL_SUITES"
    echo "Passed: $PASSED_SUITES"
    echo "Failed: $FAILED_SUITES"
    
    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ $FAILED_SUITES test suite(s) failed!${NC}"
        exit 1
    fi
}

# Execute main function
main "$@" 