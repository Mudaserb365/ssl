#!/bin/bash

# Node.js Trust Store Update Example
# This script demonstrates how to update Node.js trust stores using auto_trust_store_manager.sh

# Default values
BASELINE_TRUST_CHAIN="../baseline-certs/baseline-trust-chain.pem"
PROJECT_DIR="."
NODE_ENV_VAR="NODE_EXTRA_CA_CERTS"
VERBOSE=false

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --baseline FILE       Path to baseline trust chain (default: ../baseline-certs/baseline-trust-chain.pem)"
    echo "  -d, --directory DIR       Project directory to scan (default: current directory)"
    echo "  -e, --env-var NAME        Environment variable name for trust store path (default: NODE_EXTRA_CA_CERTS)"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 -d /path/to/nodejs/project"
    echo "  $0 -e SSL_CERT_DIR"
    exit 0
}

# Check for help flag first
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--baseline)
            BASELINE_TRUST_CHAIN="$2"
            shift 2
            ;;
        -d|--directory)
            PROJECT_DIR="$2"
            shift 2
            ;;
        -e|--env-var)
            NODE_ENV_VAR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Set verbose flag for auto_trust_store_manager.sh
VERBOSE_FLAG=""
if [ "$VERBOSE" = true ]; then
    VERBOSE_FLAG="-v"
fi

# Check if baseline trust chain exists
if [ ! -f "$BASELINE_TRUST_CHAIN" ]; then
    echo "Error: Baseline trust chain not found at $BASELINE_TRUST_CHAIN"
    exit 1
fi

# Count certificates in baseline trust chain
BASELINE_CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$BASELINE_TRUST_CHAIN")
echo "Baseline trust chain contains $BASELINE_CERT_COUNT certificates"

# Scan for Node.js trust stores in the project directory
echo "=== Scanning for Node.js trust stores in project directory ==="
../auto_trust_store_manager.sh -d "$PROJECT_DIR" $VERBOSE_FLAG | grep -E "\.pem|\.crt|\.cert"

# Update Node.js trust stores with baseline
echo "=== Updating Node.js trust stores with baseline ==="
../auto_trust_store_manager.sh -b "$BASELINE_TRUST_CHAIN" -d "$PROJECT_DIR" $VERBOSE_FLAG

# Verify the updates
echo "=== Verification after update ==="

# Find all PEM trust stores
echo "Checking PEM trust stores:"
find "$PROJECT_DIR" -type f -name "*.pem" -o -name "*.crt" -o -name "*.cert" | while read -r pem_file; do
    if grep -q "BEGIN CERTIFICATE" "$pem_file"; then
        cert_count=$(grep -c "BEGIN CERTIFICATE" "$pem_file")
        echo "PEM trust store: $pem_file contains $cert_count certificates"
        
        if [ "$cert_count" -eq "$BASELINE_CERT_COUNT" ]; then
            echo "  SUCCESS: Trust store matches baseline"
        else
            echo "  FAILURE: Trust store does not match baseline"
        fi
    fi
done

# Create or update .env file with Node.js environment variable
ENV_FILE="$PROJECT_DIR/.env"
echo "=== Setting environment variable for Node.js applications ==="
if [ -f "$ENV_FILE" ]; then
    # Update existing .env file
    if grep -q "^$NODE_ENV_VAR=" "$ENV_FILE"; then
        # Update existing variable
        sed -i.bak "s|^$NODE_ENV_VAR=.*|$NODE_ENV_VAR=$(find "$PROJECT_DIR" -type f -name "*.pem" | head -n 1)|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
        echo "Updated $NODE_ENV_VAR in $ENV_FILE"
    else
        # Add new variable
        echo "$NODE_ENV_VAR=$(find "$PROJECT_DIR" -type f -name "*.pem" | head -n 1)" >> "$ENV_FILE"
        echo "Added $NODE_ENV_VAR to $ENV_FILE"
    fi
else
    # Create new .env file
    echo "$NODE_ENV_VAR=$(find "$PROJECT_DIR" -type f -name "*.pem" | head -n 1)" > "$ENV_FILE"
    echo "Created $ENV_FILE with $NODE_ENV_VAR"
fi

echo "=== Node.js trust store update completed ==="
exit 0
