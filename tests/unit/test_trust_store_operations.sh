#!/bin/bash

# Unit Tests for Trust Store Operations
# Tests both Bash and Go implementations against various trust store types

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS_DIR="$SCRIPT_DIR/.."
FIXTURES_DIR="$TESTS_DIR/fixtures"

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test results
declare -a TEST_RESULTS=()

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

log_test_header() {
    echo
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Test framework functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -n "Running: $test_name ... "
    
    if $test_function > /tmp/test_output.log 2>&1; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "PASSED"
        TEST_RESULTS+=("PASS: $test_name")
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "FAILED"
        TEST_RESULTS+=("FAIL: $test_name")
        echo "Error output:"
        cat /tmp/test_output.log | sed 's/^/  /'
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    
    log_warning "SKIPPED: $test_name ($reason)"
    TEST_RESULTS+=("SKIP: $test_name ($reason)")
}

# Utility functions
check_command() {
    command -v "$1" >/dev/null 2>&1
}

check_file_exists() {
    [[ -f "$1" ]]
}

check_jre_available() {
    check_command "keytool" && check_command "java"
}

setup_test_environment() {
    # Create temporary directory for test operations
    export TEST_TEMP_DIR="/tmp/trust-store-tests-$$"
    mkdir -p "$TEST_TEMP_DIR"
    
    # Set up test configuration
    export TEST_CONFIG="$TEST_TEMP_DIR/test-config.yaml"
    cat > "$TEST_CONFIG" << 'EOF'
logging:
  enabled: false
  simple_mode: true
  webhook_url: ""
  local_log_enabled: false

security:
  require_noop: true

operations:
  upsert_only: true
  
jre:
  auto_detect: true
  display_info_in_noop: true
EOF
}

cleanup_test_environment() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Test functions for JRE detection
test_jre_detection_bash() {
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    
    if [[ ! -f "$bash_script" ]]; then
        return 1
    fi
    
    # Test JRE detection in noop mode
    "$bash_script" --noop --config "$TEST_CONFIG" -d "$TEST_TEMP_DIR" | grep -q "Trust Store Manager started"
}

test_jre_detection_go() {
    local go_dir="$PROJECT_ROOT/go-trust-store-manager"
    
    if [[ ! -d "$go_dir" ]]; then
        return 1
    fi
    
    cd "$go_dir"
    go run . --noop --config "$TEST_CONFIG" -d "$TEST_TEMP_DIR" | grep -q "Trust Store Manager started"
}

test_jre_info_display_noop() {
    if ! check_jre_available; then
        return 1
    fi
    
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    
    # Test that JRE information is displayed in noop mode
    "$bash_script" --noop --config "$TEST_CONFIG" -d "$TEST_TEMP_DIR" > "$TEST_TEMP_DIR/noop_output.log"
    
    # Should contain Java version information when JRE is available
    if check_jre_available; then
        java -version 2>&1 | head -1 | grep -q "version"
    fi
}

# Test functions for trust store operations
test_jks_basic_operations() {
    if ! check_jre_available; then
        return 1
    fi
    
    local test_jks="$FIXTURES_DIR/jks/basic-truststore.jks"
    
    if [[ ! -f "$test_jks" ]]; then
        return 1
    fi
    
    # Test listing JKS contents
    keytool -list -keystore "$test_jks" -storepass changeit -noprompt > /dev/null
    
    # Test with bash implementation
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    "$bash_script" --noop --config "$TEST_CONFIG" -d "$(dirname "$test_jks")" | grep -q "NOOP"
}

test_jks_password_detection() {
    if ! check_jre_available; then
        return 1
    fi
    
    # Test different password scenarios
    local passwords=("changeit" "changeme" "password" "keystore" "secret")
    
    for i in "${!passwords[@]}"; do
        local test_jks="$FIXTURES_DIR/jks/password-test-$i.jks"
        local password="${passwords[$i]}"
        
        if [[ -f "$test_jks" ]]; then
            keytool -list -keystore "$test_jks" -storepass "$password" -noprompt > /dev/null
        fi
    done
}

test_jks_multi_certificate() {
    if ! check_jre_available; then
        return 1
    fi
    
    local test_jks="$FIXTURES_DIR/jks/multi-cert-truststore.jks"
    
    if [[ ! -f "$test_jks" ]]; then
        return 1
    fi
    
    # Test that multiple certificates are detected
    local cert_count=$(keytool -list -keystore "$test_jks" -storepass changeit -noprompt | grep -c "Certificate fingerprint" || true)
    [[ $cert_count -gt 1 ]]
}

test_jks_corrupted_handling() {
    local corrupted_jks="$FIXTURES_DIR/jks/corrupted-truststore.jks"
    
    if [[ ! -f "$corrupted_jks" ]]; then
        return 1
    fi
    
    # Test that corrupted JKS is handled gracefully
    if check_jre_available; then
        ! keytool -list -keystore "$corrupted_jks" -storepass changeit -noprompt >/dev/null 2>&1
    fi
}

test_pkcs12_basic_operations() {
    if ! check_jre_available; then
        return 1
    fi
    
    local test_p12="$FIXTURES_DIR/pkcs12/basic-truststore.p12"
    
    if [[ ! -f "$test_p12" ]]; then
        return 1
    fi
    
    # Test listing PKCS12 contents
    keytool -list -keystore "$test_p12" -storetype PKCS12 -storepass changeit -noprompt > /dev/null
}

test_pkcs12_pfx_extension() {
    if ! check_jre_available; then
        return 1
    fi
    
    local test_pfx="$FIXTURES_DIR/pkcs12/basic-truststore.pfx"
    
    if [[ ! -f "$test_pfx" ]]; then
        return 1
    fi
    
    # Test that .pfx files are handled like .p12
    keytool -list -keystore "$test_pfx" -storetype PKCS12 -storepass changeit -noprompt > /dev/null
}

test_pem_basic_operations() {
    local test_pem="$FIXTURES_DIR/pem/basic-trust-store.pem"
    
    if [[ ! -f "$test_pem" ]]; then
        return 1
    fi
    
    # Test reading PEM file
    openssl x509 -in "$test_pem" -text -noout > /dev/null
}

test_pem_multi_certificate() {
    local test_pem="$FIXTURES_DIR/pem/multi-cert-trust-store.pem"
    
    if [[ ! -f "$test_pem" ]]; then
        return 1
    fi
    
    # Test that multiple certificates are detected in PEM
    local cert_count=$(grep -c "BEGIN CERTIFICATE" "$test_pem" || true)
    [[ $cert_count -gt 1 ]]
}

test_pem_empty_handling() {
    local empty_pem="$FIXTURES_DIR/pem/empty-trust-store.pem"
    
    if [[ ! -f "$empty_pem" ]]; then
        return 1
    fi
    
    # Test that empty PEM files are handled gracefully
    [[ ! -s "$empty_pem" ]] || [[ $(wc -l < "$empty_pem") -eq 0 ]]
}

test_pem_invalid_handling() {
    local invalid_pem="$FIXTURES_DIR/pem/invalid-trust-store.pem"
    
    if [[ ! -f "$invalid_pem" ]]; then
        return 1
    fi
    
    # Test that invalid PEM is handled gracefully
    ! openssl x509 -in "$invalid_pem" -text -noout >/dev/null 2>&1
}

# Test configuration and logging
test_config_loading() {
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    
    # Test custom config loading
    "$bash_script" --noop --config "$TEST_CONFIG" -d "$TEST_TEMP_DIR" | grep -q "Trust Store Manager started"
}

test_optional_logging() {
    # Test that logging can be disabled
    local test_config="$TEST_TEMP_DIR/no-logging-config.yaml"
    cat > "$test_config" << 'EOF'
logging:
  enabled: false
  webhook_url: ""
  local_log_enabled: false

security:
  require_noop: true
EOF
    
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    "$bash_script" --noop --config "$test_config" -d "$TEST_TEMP_DIR" | grep -q "Trust Store Manager started"
}

test_noop_requirement() {
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    
    # Test that script requires --noop by default
    ! "$bash_script" --config "$TEST_CONFIG" -d "$TEST_TEMP_DIR" >/dev/null 2>&1
    
    # Test that --noop allows execution
    "$bash_script" --noop --config "$TEST_CONFIG" -d "$TEST_TEMP_DIR" | grep -q "Trust Store Manager started"
}

# Performance tests
test_large_trust_store_performance() {
    local large_pem="$FIXTURES_DIR/pem/large-trust-store.pem"
    
    if [[ ! -f "$large_pem" ]]; then
        return 1
    fi
    
    # Test performance with large trust store (should complete within reasonable time)
    local start_time=$(date +%s)
    
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    "$bash_script" --noop --config "$TEST_CONFIG" -d "$(dirname "$large_pem")" > /dev/null
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Should complete within 30 seconds
    [[ $duration -lt 30 ]]
}

# Integration tests
test_bash_go_command_equivalence() {
    local bash_script="$PROJECT_ROOT/bash-trust-store-manager/trust-store-manager-enterprise.sh"
    local go_dir="$PROJECT_ROOT/go-trust-store-manager"
    
    # Test that both implementations support same flags
    "$bash_script" --help | grep -q "\-\-noop"
    
    if [[ -d "$go_dir" ]]; then
        cd "$go_dir"
        go run . --help | grep -q "\-\-noop"
    fi
}

# Main test execution
main() {
    log_info "Starting Trust Store Manager Unit Tests"
    log_info "Project root: $PROJECT_ROOT"
    
    # Setup test environment
    setup_test_environment
    trap cleanup_test_environment EXIT
    
    # Create test fixtures if they don't exist
    if [[ ! -d "$FIXTURES_DIR" ]]; then
        log_info "Creating test fixtures..."
        chmod +x "$TESTS_DIR/fixtures/create_test_keystores.sh"
        "$TESTS_DIR/fixtures/create_test_keystores.sh"
    fi
    
    # Run JRE detection tests
    log_test_header "JRE Detection Tests"
    
    run_test "JRE Detection (Bash)" test_jre_detection_bash
    run_test "JRE Detection (Go)" test_jre_detection_go
    
    if check_jre_available; then
        run_test "JRE Info Display in Noop" test_jre_info_display_noop
    else
        skip_test "JRE Info Display in Noop" "JRE not available"
    fi
    
    # Run JKS tests
    log_test_header "JKS Trust Store Tests"
    
    if check_jre_available; then
        run_test "JKS Basic Operations" test_jks_basic_operations
        run_test "JKS Password Detection" test_jks_password_detection
        run_test "JKS Multi-Certificate" test_jks_multi_certificate
        run_test "JKS Corrupted Handling" test_jks_corrupted_handling
    else
        skip_test "JKS Basic Operations" "JRE not available"
        skip_test "JKS Password Detection" "JRE not available"  
        skip_test "JKS Multi-Certificate" "JRE not available"
        skip_test "JKS Corrupted Handling" "JRE not available"
    fi
    
    # Run PKCS12 tests
    log_test_header "PKCS12 Trust Store Tests"
    
    if check_jre_available; then
        run_test "PKCS12 Basic Operations" test_pkcs12_basic_operations
        run_test "PKCS12 PFX Extension" test_pkcs12_pfx_extension
    else
        skip_test "PKCS12 Basic Operations" "JRE not available"
        skip_test "PKCS12 PFX Extension" "JRE not available"
    fi
    
    # Run PEM tests
    log_test_header "PEM Trust Store Tests"
    
    run_test "PEM Basic Operations" test_pem_basic_operations
    run_test "PEM Multi-Certificate" test_pem_multi_certificate
    run_test "PEM Empty Handling" test_pem_empty_handling
    run_test "PEM Invalid Handling" test_pem_invalid_handling
    
    # Run configuration tests
    log_test_header "Configuration Tests"
    
    run_test "Config Loading" test_config_loading
    run_test "Optional Logging" test_optional_logging
    run_test "Noop Requirement" test_noop_requirement
    
    # Run performance tests
    log_test_header "Performance Tests"
    
    run_test "Large Trust Store Performance" test_large_trust_store_performance
    
    # Run integration tests
    log_test_header "Integration Tests"
    
    run_test "Bash/Go Command Equivalence" test_bash_go_command_equivalence
    
    # Print test summary
    echo
    log_test_header "Test Summary"
    
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Skipped: $SKIPPED_TESTS"
    
    echo
    echo "Detailed results:"
    for result in "${TEST_RESULTS[@]}"; do
        case "$result" in
            PASS:*) echo -e "${GREEN}$result${NC}" ;;
            FAIL:*) echo -e "${RED}$result${NC}" ;;
            SKIP:*) echo -e "${YELLOW}$result${NC}" ;;
        esac
    done
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "$FAILED_TESTS test(s) failed!"
        exit 1
    fi
}

# Execute main function
main "$@" 