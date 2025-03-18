#!/bin/bash

# Trust Chain Validation Test Suite
# This script runs validation tests on updated trust stores to ensure
# they work correctly with both webserver and MTLS connections.

# Default values
SCAN_DIR="."
WEBSERVER_HOST="localhost"
WEBSERVER_PORT="443"
OUTPUT_FILE=""
VERBOSE=false
WAIT_BEFORE_TEST=5  # Seconds to wait before testing (allow servers to reload)

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -d, --scan-dir DIR       Directory to scan for trust stores (default: current directory)"
    echo "  -h, --host HOST          Webserver hostname to test against (default: localhost)"
    echo "  -p, --port PORT          Webserver port to test against (default: 443)"
    echo "  -w, --wait SECONDS       Wait time in seconds before running tests (default: 5)"
    echo "  -o, --output FILE        Save test results to specified JSON file"
    echo "  -v, --verbose            Enable verbose output"
    echo "  --help                   Display this help message"
    echo
    echo "Example:"
    echo "  $0 -d /path/to/trust/stores -h example.com -p 443 -o results.json"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--scan-dir)
            SCAN_DIR="$2"
            shift 2
            ;;
        -h|--host)
            WEBSERVER_HOST="$2"
            shift 2
            ;;
        -p|--port)
            WEBSERVER_PORT="$2"
            shift 2
            ;;
        -w|--wait)
            WAIT_BEFORE_TEST="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Set up verbose flag
VERBOSE_FLAG=""
if [ "$VERBOSE" = true ]; then
    VERBOSE_FLAG="-v"
fi

# Set up output flag
OUTPUT_FLAG=""
if [ -n "$OUTPUT_FILE" ]; then
    OUTPUT_FLAG="-o $OUTPUT_FILE"
fi

# Find the path to the validator script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
VALIDATOR_SCRIPT="$SCRIPT_DIR/trust_chain_validator.py"

# Check if the validator script exists
if [ ! -f "$VALIDATOR_SCRIPT" ]; then
    echo "Error: Validator script not found at $VALIDATOR_SCRIPT"
    exit 1
fi

# Print test information
echo "===== Trust Chain Validation Tests ====="
echo "Scan directory: $SCAN_DIR"
echo "Target webserver: $WEBSERVER_HOST:$WEBSERVER_PORT"
echo "Validator script: $VALIDATOR_SCRIPT"
echo "========================================"

# Wait before running tests (to allow servers to reload)
if [ "$WAIT_BEFORE_TEST" -gt 0 ]; then
    echo "Waiting for $WAIT_BEFORE_TEST seconds before running tests..."
    sleep "$WAIT_BEFORE_TEST"
fi

# Run the validation tests
echo "Starting validation tests..."
python3 "$VALIDATOR_SCRIPT" \
    --scan-dir "$SCAN_DIR" \
    --host "$WEBSERVER_HOST" \
    --port "$WEBSERVER_PORT" \
    $OUTPUT_FLAG $VERBOSE_FLAG

# Check the exit code
TEST_RESULT=$?
if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ Trust chain validation tests PASSED"
    exit 0
else
    echo "❌ Trust chain validation tests FAILED"
    exit 1
fi 