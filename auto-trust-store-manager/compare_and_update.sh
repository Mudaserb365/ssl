#!/bin/bash
# Script to compare and update project trust stores with a baseline trust chain

# Default values
BASELINE_TRUST_CHAIN="baseline-certs/baseline-trust-chain.pem"
PROJECT_ROOT="."
JKS_PASSWORDS="changeit changeme password keystore truststore secret"
BASELINE_URL="https://truststore.example.com/baseline-trust-chain.pem"
RUN_TESTS=true
VERBOSE=false

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --baseline FILE       Path to baseline trust chain (default: baseline-certs/baseline-trust-chain.pem)"
    echo "  -d, --directory DIR       Target directory to scan (default: current directory)"
    echo "  -p, --passwords \"p1 p2\"   Space-separated list of passwords to try for JKS files (in quotes)"
    echo "  -u, --baseline-url URL    URL to download baseline trust chain (default: $BASELINE_URL)"
    echo "  -t, --skip-tests          Skip running validation tests after updates"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 -d /path/to/project"
    echo "  $0 -b /path/to/baseline.pem"
    echo "  $0 -p \"password1 password2 password3\""
    echo "  $0 -u https://example.com/baseline.pem"
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
            PROJECT_ROOT="$2"
            shift 2
            ;;
        -p|--passwords)
            JKS_PASSWORDS="$2"
            shift 2
            ;;
        -u|--baseline-url)
            BASELINE_URL="$2"
            shift 2
            ;;
        -t|--skip-tests)
            RUN_TESTS=false
            shift
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

# Function to handle errors with JKS trust stores
handle_jks_error() {
    echo "ERROR: Could not access one or more JKS trust stores."
    echo "Please provide the correct passwords using the -p option."
    echo "Current passwords to try: $JKS_PASSWORDS"
    exit 1
}

# First try to download baseline trust chain from URL
TEMP_BASELINE="/tmp/baseline-trust-chain-$$.pem"
echo "Downloading baseline trust chain from $BASELINE_URL..."
if curl -s --fail "$BASELINE_URL" -o "$TEMP_BASELINE"; then
    echo "Successfully downloaded baseline trust chain from URL"
    BASELINE_TRUST_CHAIN="$TEMP_BASELINE"
elif [ -f "$BASELINE_TRUST_CHAIN" ]; then
    echo "Failed to download from URL, using local file: $BASELINE_TRUST_CHAIN"
else
    echo "Failed to download from URL and local file not found: $BASELINE_TRUST_CHAIN"
    exit 1
fi

# Count certificates in baseline trust chain
BASELINE_CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$BASELINE_TRUST_CHAIN")
echo "Baseline trust chain contains $BASELINE_CERT_COUNT certificates"

# Set verbose flag for auto_trust_store_manager.sh
VERBOSE_FLAG=""
if [ "$VERBOSE" = true ]; then
    VERBOSE_FLAG="-v"
fi

# Scan for trust stores in the project directories
echo "=== Scanning for trust stores in project directories ==="
./auto_trust_store_manager.sh -d "$PROJECT_ROOT" $VERBOSE_FLAG

# Compare trust stores with baseline
echo "=== Comparing trust stores with baseline ==="
./auto_trust_store_manager.sh -b "$BASELINE_TRUST_CHAIN" -d "$PROJECT_ROOT" -p "$JKS_PASSWORDS" -C $VERBOSE_FLAG || handle_jks_error

# Update trust stores with baseline
echo "=== Updating trust stores with baseline ==="
./auto_trust_store_manager.sh -b "$BASELINE_TRUST_CHAIN" -d "$PROJECT_ROOT" -p "$JKS_PASSWORDS" $VERBOSE_FLAG || handle_jks_error

# Verify the updates
echo "=== Verification after update ==="

# Find all PEM trust stores
echo "Checking PEM trust stores:"
find "$PROJECT_ROOT" -type f -name "*.pem" -o -name "*.crt" -o -name "*.cert" | grep -v "baseline-certs" | while read -r pem_file; do
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

# Find all JKS trust stores
echo "Checking JKS trust stores:"
find "$PROJECT_ROOT" -type f -name "*.jks" -o -name "*.keystore" -o -name "*.truststore" | while read -r jks_file; do
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

# Run validation tests if enabled
if [ "$RUN_TESTS" = true ]; then
    echo "=== Running validation tests ==="
    if [ -f "./test_truststore.sh" ]; then
        ./test_truststore.sh
    else
        echo "Test script not found. Skipping validation tests."
    fi
fi

# Clean up temporary file if it exists
if [ -f "$TEMP_BASELINE" ]; then
    rm -f "$TEMP_BASELINE"
fi

echo "=== Trust store update completed ==="
