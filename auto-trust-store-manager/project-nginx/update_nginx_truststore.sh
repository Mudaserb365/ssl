#!/bin/bash

# Nginx Trust Store Update Example
# This script demonstrates how to update Nginx trust stores using auto_trust_store_manager.sh

# Default values
BASELINE_TRUST_CHAIN="../baseline-certs/baseline-trust-chain.pem"
NGINX_CONF_DIR="./conf"
NGINX_CERTS_DIR="./certs"
VERBOSE=false
RUN_VALIDATION=false
WEBSERVER_HOST="localhost"
WEBSERVER_PORT="443"

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --baseline FILE       Path to baseline trust chain (default: ../baseline-certs/baseline-trust-chain.pem)"
    echo "  -c, --conf-dir DIR        Nginx configuration directory (default: ./conf)"
    echo "  -d, --certs-dir DIR       Nginx certificates directory (default: ./certs)"
    echo "  -t, --test                Run validation tests after updating trust stores"
    echo "  --host HOST               Host to test against (default: localhost)"
    echo "  --port PORT               Port to test against (default: 443)"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 -c /etc/nginx/conf.d -d /etc/nginx/certs"
    echo "  $0 -b /path/to/custom/baseline.pem"
    echo "  $0 -t --host example.com --port 443"
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
        -c|--conf-dir)
            NGINX_CONF_DIR="$2"
            shift 2
            ;;
        -d|--certs-dir)
            NGINX_CERTS_DIR="$2"
            shift 2
            ;;
        -t|--test)
            RUN_VALIDATION=true
            shift
            ;;
        --host)
            WEBSERVER_HOST="$2"
            shift 2
            ;;
        --port)
            WEBSERVER_PORT="$2"
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

# Function to extract trust store paths from Nginx configuration files
find_nginx_trust_stores() {
    local trust_stores=()
    
    # Find all configuration files in the Nginx configuration directory
    echo "Scanning Nginx configuration files in $NGINX_CONF_DIR"
    find "$NGINX_CONF_DIR" -type f -name "*.conf" | while read -r conf_file; do
        echo "Analyzing configuration file: $conf_file"
        
        # Extract trust store paths from Nginx configuration files
        grep -o "ssl_trusted_certificate.*;" "$conf_file" 2>/dev/null | while read -r line; do
            if [[ "$line" =~ ssl_trusted_certificate[[:space:]]+(.+)\; ]]; then
                path=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d "'\"")
                
                # Handle relative and absolute paths
                if [[ ! "$path" = /* ]]; then
                    # Convert paths like /etc/nginx/certs/ca-trust-store.pem to actual paths
                    relative_path=$(echo "$path" | sed 's|/etc/nginx/certs|'"$NGINX_CERTS_DIR"'|g')
                    echo "Found relative trust store path: $path -> $relative_path"
                    trust_stores+=("$relative_path")
                else
                    echo "Found absolute trust store path: $path"
                    trust_stores+=("$path")
                fi
            fi
        done
    done
    
    # Return the list of trust stores
    echo "${trust_stores[@]}"
}

# Scan for Nginx trust stores
echo "=== Scanning for Nginx trust stores ==="
TRUST_STORES=$(find_nginx_trust_stores)

# Update each trust store with the baseline
echo "=== Updating Nginx trust stores with baseline ==="
for trust_store in $TRUST_STORES; do
    echo "Updating trust store: $trust_store"
    cp "$BASELINE_TRUST_CHAIN" "$trust_store"
done

# If no trust stores were found in configuration, update the default trust store
if [ -z "$TRUST_STORES" ]; then
    echo "No trust stores found in Nginx configuration, updating default trust store"
    DEFAULT_TRUST_STORE="$NGINX_CERTS_DIR/ca-trust-store.pem"
    echo "Updating default trust store: $DEFAULT_TRUST_STORE"
    cp "$BASELINE_TRUST_CHAIN" "$DEFAULT_TRUST_STORE"
    echo "Remember to add the following to your Nginx server configuration:"
    echo "    ssl_trusted_certificate $DEFAULT_TRUST_STORE;"
fi

# Verify the updates
echo "=== Verification after update ==="
find "$NGINX_CERTS_DIR" -name "*.pem" | while read -r pem_file; do
    if grep -q "BEGIN CERTIFICATE" "$pem_file"; then
        cert_count=$(grep -c "BEGIN CERTIFICATE" "$pem_file")
        echo "Trust store: $pem_file contains $cert_count certificates"
        
        if [ "$cert_count" -eq "$BASELINE_CERT_COUNT" ]; then
            echo "  SUCCESS: Trust store matches baseline"
        else
            echo "  FAILURE: Trust store does not match baseline"
        fi
    fi
done

# Run validation tests if enabled
if [ "$RUN_VALIDATION" = true ]; then
    echo "=== Running validation tests ==="
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    VALIDATION_SCRIPT="$SCRIPT_DIR/../../test-suite/run_validation_tests.sh"
    
    if [ -f "$VALIDATION_SCRIPT" ]; then
        # Set verbose flag for validation script
        VALIDATION_VERBOSE=""
        if [ "$VERBOSE" = true ]; then
            VALIDATION_VERBOSE="-v"
        fi
        
        # Run validation tests
        "$VALIDATION_SCRIPT" \
            -d "$NGINX_CERTS_DIR" \
            -h "$WEBSERVER_HOST" \
            -p "$WEBSERVER_PORT" \
            $VALIDATION_VERBOSE
        
        VALIDATION_RESULT=$?
        if [ $VALIDATION_RESULT -eq 0 ]; then
            echo "✅ Trust store validation tests PASSED"
        else
            echo "❌ Trust store validation tests FAILED"
            echo "Warning: Trust stores were updated but validation tests failed."
            echo "You may need to check your Nginx configuration or connectivity."
            echo "Remember to reload Nginx after updating trust stores."
        fi
    else
        echo "Warning: Validation script not found at $VALIDATION_SCRIPT"
        echo "Skipping validation tests."
    fi
fi

echo "=== Nginx trust store update completed ==="
echo "Note: Remember to reload Nginx after updating trust stores:"
echo "    nginx -t && systemctl reload nginx"
exit 0
