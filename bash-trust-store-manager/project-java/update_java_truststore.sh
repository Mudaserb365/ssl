#!/bin/bash

# Java Trust Store Update Example
# This script demonstrates how to update Java trust stores using auto_trust_store_manager.sh

# Default values
BASELINE_TRUST_CHAIN="../baseline-certs/baseline-trust-chain.pem"
PROJECT_DIR="."
JKS_PASSWORDS="changeit changeme password keystore truststore secret"
VERBOSE=false

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --baseline FILE       Path to baseline trust chain (default: ../baseline-certs/baseline-trust-chain.pem)"
    echo "  -d, --directory DIR       Project directory to scan (default: current directory)"
    echo "  -p, --passwords \"p1 p2\"   Space-separated list of JKS passwords to try (in quotes)"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 -d /path/to/java/project"
    echo "  $0 -p \"password1 password2 password3\""
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
        -p|--passwords)
            JKS_PASSWORDS="$2"
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

# Scan for Java trust stores in the project directory
echo "=== Scanning for Java trust stores in project directory ==="
../auto_trust_store_manager.sh -d "$PROJECT_DIR" $VERBOSE_FLAG | grep -E "\.jks|\.keystore|\.truststore"

# Update Java trust stores with baseline
echo "=== Updating Java trust stores with baseline ==="
../auto_trust_store_manager.sh -b "$BASELINE_TRUST_CHAIN" -d "$PROJECT_DIR" -p "$JKS_PASSWORDS" $VERBOSE_FLAG

# Verify the updates
echo "=== Verification after update ==="

# Find all JKS trust stores
echo "Checking JKS trust stores:"
find "$PROJECT_DIR" -type f -name "*.jks" -o -name "*.keystore" -o -name "*.truststore" | while read -r jks_file; do
    success=false
    
    # Try each password
    for password in $JKS_PASSWORDS; do
        cert_count=$(keytool -list -keystore "$jks_file" -storepass "$password" 2>/dev/null | grep -c "Certificate fingerprint")
        if [ $? -eq 0 ]; then
            echo "JKS trust store: $jks_file contains $cert_count certificates (password: $password)"
            
            if [ "$cert_count" -eq "$BASELINE_CERT_COUNT" ]; then
                echo "  SUCCESS: Trust store matches baseline"
            else
                echo "  FAILURE: Trust store does not match baseline"
            fi
            
            success=true
            break
        fi
    done
    
    if [ "$success" = false ]; then
        echo "JKS trust store: $jks_file - COULD NOT ACCESS (tried passwords: $JKS_PASSWORDS)"
    fi
done

echo "=== Java trust store update completed ==="
exit 0
