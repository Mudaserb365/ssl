#!/bin/bash
#
# Automated Trust-Store Manager
# This script automates the discovery and modification of trust-store files in various runtimes,
# containers, and web servers.
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TARGET_DIR="."
TEST_CERT_PATH=""
DEFAULT_CERT_PATH="/tmp/test-cert.pem"
LOG_FILE="trust_store_scan_$(date +%Y%m%d_%H%M%S).log"
VERBOSE=false
BACKUP=true
RESTART_SERVICES=false
COMMON_PASSWORDS=("changeit" "changeme" "password" "keystore" "truststore" "secret" "")
SUMMARY_SUCCESS=0
SUMMARY_FAILURE=0
KUBERNETES_MODE=false
DOCKER_MODE=false
BASELINE_URL=""
BASELINE_STORE="/tmp/baseline_trust_store_$(date +%s)"
COMPARE_MODE=false

# Create a test certificate if none provided
create_test_certificate() {
    if [ ! -f "$DEFAULT_CERT_PATH" ]; then
        log_info "Creating test certificate at $DEFAULT_CERT_PATH"
        openssl req -x509 -newkey rsa:4096 -keyout /tmp/test-key.pem -out "$DEFAULT_CERT_PATH" -days 365 -nodes -subj "/CN=Test Certificate/O=Trust Store Scanner/C=US" 2>/dev/null
    fi
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
    ((SUMMARY_SUCCESS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    ((SUMMARY_FAILURE++))
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "[DEBUG] $1" | tee -a "$LOG_FILE"
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [options]

Options:
  -d, --directory DIR       Target directory to scan (default: current directory)
  -c, --certificate FILE    Path to certificate to append (default: auto-generated)
  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)
  -p, --passwords "p1 p2"   Space-separated list of passwords to try (in quotes)
  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)
  -D, --docker              Enable Docker mode (scan common Docker trust store locations)
  -r, --restart             Restart affected services after modification
  -n, --no-backup           Disable backup creation before modification
  -v, --verbose             Enable verbose output
  -b, --baseline URL        URL to download baseline trust store for comparison
  -C, --compare-only        Only compare trust stores, don't modify them
  -h, --help                Display this help message

Examples:
  $0 -d /path/to/project -c /path/to/cert.pem
  $0 --kubernetes --restart
  $0 --docker -v
  $0 -b https://example.com/baseline.pem -C
EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--directory)
                TARGET_DIR="$2"
                shift 2
                ;;
            -c|--certificate)
                TEST_CERT_PATH="$2"
                shift 2
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -p|--passwords)
                IFS=' ' read -r -a COMMON_PASSWORDS <<< "$2"
                shift 2
                ;;
            -k|--kubernetes)
                KUBERNETES_MODE=true
                shift
                ;;
            -D|--docker)
                DOCKER_MODE=true
                shift
                ;;
            -r|--restart)
                RESTART_SERVICES=true
                shift
                ;;
            -n|--no-backup)
                BACKUP=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -b|--baseline)
                BASELINE_URL="$2"
                shift 2
                ;;
            -C|--compare-only)
                COMPARE_MODE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate arguments
    if [ ! -d "$TARGET_DIR" ]; then
        log_error "Directory does not exist: $TARGET_DIR"
        exit 1
    fi

    # Use provided certificate or create a test one
    if [ -z "$TEST_CERT_PATH" ]; then
        TEST_CERT_PATH="$DEFAULT_CERT_PATH"
        create_test_certificate
    elif [ ! -f "$TEST_CERT_PATH" ]; then
        log_error "Certificate file does not exist: $TEST_CERT_PATH"
        exit 1
    fi

    # Additional validation for baseline URL
    if [ -n "$BASELINE_URL" ]; then
        if ! download_baseline_store; then
            exit 1
        fi
    fi
}

# Check for required tools
check_dependencies() {
    local missing_deps=false
    
    # Check for basic dependencies
    for cmd in openssl find grep sed awk; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing_deps=true
        fi
    done
    
    # Check for keytool specifically
    KEYTOOL_PATH=$(find_keytool)
    if [ -z "$KEYTOOL_PATH" ]; then
        missing_deps=true
    else
        # Export the keytool path for use in other functions
        export KEYTOOL_PATH
        # Create an alias to ensure we use the found keytool
        alias keytool="$KEYTOOL_PATH"
    fi
    
    if [ "$missing_deps" = true ]; then
        log_error "Please install missing dependencies and try again."
        exit 1
    fi
}

# Create backup of a file
create_backup() {
    local file="$1"
    local backup_file="${file}.bak.$(date +%Y%m%d_%H%M%S)"
    
    if [ "$BACKUP" = true ]; then
        cp "$file" "$backup_file"
        log_debug "Created backup: $backup_file"
        echo "$backup_file"
    else
        log_debug "Backup disabled, skipping backup creation for $file"
        echo ""
    fi
}

# Detect file type
detect_file_type() {
    local file="$1"
    local file_type=""
    
    # Check file extension
    case "$file" in
        *.jks|*.keystore|*.truststore)
            file_type="JKS"
            ;;
        *.p12|*.pfx)
            file_type="PKCS12"
            ;;
        *.pem|*.crt|*.cer|*.cert)
            file_type="PEM"
            ;;
        *)
            # Try to determine by content
            if file "$file" | grep -q "Java KeyStore"; then
                file_type="JKS"
            elif file "$file" | grep -q "PKCS12"; then
                file_type="PKCS12"
            elif grep -q "BEGIN CERTIFICATE" "$file" 2>/dev/null; then
                file_type="PEM"
            else
                file_type="UNKNOWN"
            fi
            ;;
    esac
    
    echo "$file_type"
}

# Handle JKS trust store
handle_jks() {
    local file="$1"
    local success=false
    local alias="trust-store-scanner-$(date +%s)"
    
    log_info "Processing JKS trust store: $file"
    
    # Try each password
    for password in "${COMMON_PASSWORDS[@]}"; do
        log_debug "Trying password: ${password:-<empty>}"
        
        if keytool -list -keystore "$file" -storepass "$password" &>/dev/null; then
            log_success "Successfully accessed JKS with password: ${password:-<empty>}"
            
            # Create backup
            local backup_file=$(create_backup "$file")
            
            # Try to import the certificate
            if keytool -importcert -noprompt -keystore "$file" -storepass "$password" -alias "$alias" -file "$TEST_CERT_PATH" &>/dev/null; then
                log_success "Successfully imported certificate to $file with alias $alias"
                
                # Verify the import
                if keytool -list -keystore "$file" -storepass "$password" -alias "$alias" &>/dev/null; then
                    log_success "Verified certificate import to $file"
                    success=true
                    
                    # Generate command to remove the test certificate if needed
                    echo "# To remove the test certificate:" >> "$LOG_FILE"
                    echo "keytool -delete -keystore \"$file\" -storepass \"$password\" -alias \"$alias\"" >> "$LOG_FILE"
                else
                    log_error "Failed to verify certificate import to $file"
                    # Restore from backup if available
                    if [ -n "$backup_file" ]; then
                        cp "$backup_file" "$file"
                        log_info "Restored from backup: $backup_file"
                    fi
                fi
            else
                log_error "Failed to import certificate to $file"
            fi
            
            break
        fi
    done
    
    if [ "$success" = false ]; then
        log_error "Could not access JKS file $file with any of the provided passwords"
    fi
    
    return $success
}

# Handle PKCS12 trust store
handle_pkcs12() {
    local file="$1"
    local success=false
    local temp_pem="/tmp/pkcs12_extract_$(date +%s).pem"
    
    log_info "Processing PKCS12 trust store: $file"
    
    # Try each password
    for password in "${COMMON_PASSWORDS[@]}"; do
        log_debug "Trying password: ${password:-<empty>}"
        
        if openssl pkcs12 -in "$file" -nokeys -passin "pass:$password" -out "$temp_pem" &>/dev/null; then
            log_success "Successfully accessed PKCS12 with password: ${password:-<empty>}"
            
            # Create backup
            local backup_file=$(create_backup "$file")
            
            # Extract certificates to PEM
            openssl pkcs12 -in "$file" -nokeys -passin "pass:$password" -out "$temp_pem" &>/dev/null
            
            # Append new certificate
            cat "$TEST_CERT_PATH" >> "$temp_pem"
            
            # Convert back to PKCS12
            if openssl pkcs12 -export -in "$temp_pem" -nokeys -passout "pass:$password" -out "$file" &>/dev/null; then
                log_success "Successfully updated PKCS12 file $file"
                success=true
            else
                log_error "Failed to update PKCS12 file $file"
                # Restore from backup if available
                if [ -n "$backup_file" ]; then
                    cp "$backup_file" "$file"
                    log_info "Restored from backup: $backup_file"
                fi
            fi
            
            # Clean up
            rm -f "$temp_pem"
            break
        fi
    done
    
    if [ "$success" = false ]; then
        log_error "Could not access PKCS12 file $file with any of the provided passwords"
    fi
    
    return $success
}

# Handle PEM trust store
handle_pem() {
    local file="$1"
    
    log_info "Processing PEM trust store: $file"
    
    # Check if file is readable
    if [ ! -r "$file" ]; then
        log_error "PEM file $file is not readable"
        return 1
    fi
    
    # Create backup
    local backup_file=$(create_backup "$file")
    
    # Append certificate
    if cat "$TEST_CERT_PATH" >> "$file"; then
        log_success "Successfully appended certificate to PEM file $file"
        return 0
    else
        log_error "Failed to append certificate to PEM file $file"
        # Restore from backup if available
        if [ -n "$backup_file" ]; then
            cp "$backup_file" "$file"
            log_info "Restored from backup: $backup_file"
        fi
        return 1
    fi
}

# Extract trust store paths from configuration files
extract_config_paths() {
    local dir="$1"
    local found_paths=()
    
    log_info "Extracting trust store paths from configuration files in $dir"
    
    # Java properties files
    while IFS= read -r file; do
        log_debug "Checking Java properties file: $file"
        
        # Extract paths from properties files
        while IFS= read -r line; do
            if [[ "$line" =~ (trustStore|trust-store|truststore).*=(.+) ]]; then
                path=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Handle relative paths
                if [[ ! "$path" = /* ]]; then
                    path="$(dirname "$file")/$path"
                fi
                log_debug "Found trust store path in config: $path"
                found_paths+=("$path")
            fi
        done < "$file"
    done < <(find "$dir" -type f -name "*.properties" -o -name "*.conf" -o -name "*.xml" -o -name "*.yaml" -o -name "*.yml" | grep -v "node_modules" | grep -v ".git")
    
    # Environment files
    while IFS= read -r file; do
        log_debug "Checking environment file: $file"
        
        # Extract paths from .env files
        while IFS= read -r line; do
            if [[ "$line" =~ (TRUSTSTORE|TRUST_STORE).*=(.+) ]]; then
                path=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Handle relative paths
                if [[ ! "$path" = /* ]]; then
                    path="$(dirname "$file")/$path"
                fi
                log_debug "Found trust store path in env file: $path"
                found_paths+=("$path")
            fi
        done < "$file"
    done < <(find "$dir" -type f -name ".env*" | grep -v "node_modules" | grep -v ".git")
    
    # Node.js files
    while IFS= read -r file; do
        log_debug "Checking Node.js file: $file"
        
        # Extract paths from Node.js files
        grep -o "NODE_EXTRA_CA_CERTS.*=.*" "$file" 2>/dev/null | while read -r line; do
            if [[ "$line" =~ NODE_EXTRA_CA_CERTS.*=(.+) ]]; then
                path=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d "'\"")
                # Handle relative paths
                if [[ ! "$path" = /* ]]; then
                    path="$(dirname "$file")/$path"
                fi
                log_debug "Found trust store path in Node.js file: $path"
                found_paths+=("$path")
            fi
        done
    done < <(find "$dir" -type f -name "*.js" -o -name "*.json" | grep -v "node_modules" | grep -v ".git")
    
    # Web server config files
    while IFS= read -r file; do
        log_debug "Checking web server config file: $file"
        
        # Extract paths from Nginx/Apache config files
        grep -o "ssl_trusted_certificate.*;" "$file" 2>/dev/null | while read -r line; do
            if [[ "$line" =~ ssl_trusted_certificate[[:space:]]+(.+); ]]; then
                path=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d "'\"")
                # Handle relative paths
                if [[ ! "$path" = /* ]]; then
                    path="$(dirname "$file")/$path"
                fi
                log_debug "Found trust store path in web server config: $path"
                found_paths+=("$path")
            fi
        done
        
        grep -o "SSLCACertificateFile.*" "$file" 2>/dev/null | while read -r line; do
            if [[ "$line" =~ SSLCACertificateFile[[:space:]]+(.+) ]]; then
                path=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d "'\"")
                # Handle relative paths
                if [[ ! "$path" = /* ]]; then
                    path="$(dirname "$file")/$path"
                fi
                log_debug "Found trust store path in web server config: $path"
                found_paths+=("$path")
            fi
        done
    done < <(find "$dir" -type f -name "*.conf" -o -name "httpd.conf" -o -name "apache2.conf" -o -name "nginx.conf" | grep -v "node_modules" | grep -v ".git")
    
    # Return unique paths
    printf '%s\n' "${found_paths[@]}" | sort -u
}

# Scan for trust stores in a directory
scan_directory() {
    local dir="$1"
    local trust_stores=()
    
    log_info "Scanning directory: $dir"
    
    # Find files by extension
    while IFS= read -r file; do
        trust_stores+=("$file")
    done < <(find "$dir" -type f \( -name "*.jks" -o -name "*.keystore" -o -name "*.truststore" -o -name "*.p12" -o -name "*.pfx" -o -name "*.pem" -o -name "*.crt" -o -name "*.cer" -o -name "*.cert" \) 2>/dev/null | grep -v "node_modules" | grep -v ".git")
    
    # Extract paths from configuration files
    while IFS= read -r path; do
        if [ -f "$path" ]; then
            trust_stores+=("$path")
        fi
    done < <(extract_config_paths "$dir")
    
    # Return unique paths
    printf '%s\n' "${trust_stores[@]}" | sort -u
}

# Scan Kubernetes resources for trust stores
scan_kubernetes() {
    log_info "Scanning Kubernetes resources for trust stores"
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl command not found, cannot scan Kubernetes resources"
        return 1
    fi
    
    local temp_dir=$(mktemp -d)
    local trust_stores=()
    
    # Scan ConfigMaps
    log_debug "Scanning Kubernetes ConfigMaps"
    kubectl get configmaps --all-namespaces -o json | jq -r '.items[] | select(.data | keys[] | test(".*\\.(jks|keystore|truststore|p12|pfx|pem|crt|cer|cert)$")) | .metadata.namespace + "/" + .metadata.name' | while read -r cm; do
        namespace=$(echo "$cm" | cut -d'/' -f1)
        name=$(echo "$cm" | cut -d'/' -f2)
        
        log_debug "Found potential trust store in ConfigMap: $namespace/$name"
        
        # Extract data keys
        kubectl get configmap -n "$namespace" "$name" -o json | jq -r '.data | keys[]' | while read -r key; do
            if [[ "$key" =~ \.(jks|keystore|truststore|p12|pfx|pem|crt|cer|cert)$ ]]; then
                log_info "Extracting trust store from ConfigMap: $namespace/$name/$key"
                
                # Save to temp file
                local temp_file="$temp_dir/${namespace}_${name}_${key}"
                kubectl get configmap -n "$namespace" "$name" -o jsonpath="{.data['$key']}" > "$temp_file"
                
                trust_stores+=("$temp_file")
            fi
        done
    done
    
    # Scan Secrets
    log_debug "Scanning Kubernetes Secrets"
    kubectl get secrets --all-namespaces -o json | jq -r '.items[] | select(.data | keys[] | test(".*\\.(jks|keystore|truststore|p12|pfx|pem|crt|cer|cert)$")) | .metadata.namespace + "/" + .metadata.name' | while read -r secret; do
        namespace=$(echo "$secret" | cut -d'/' -f1)
        name=$(echo "$secret" | cut -d'/' -f2)
        
        log_debug "Found potential trust store in Secret: $namespace/$name"
        
        # Extract data keys
        kubectl get secret -n "$namespace" "$name" -o json | jq -r '.data | keys[]' | while read -r key; do
            if [[ "$key" =~ \.(jks|keystore|truststore|p12|pfx|pem|crt|cer|cert)$ ]]; then
                log_info "Extracting trust store from Secret: $namespace/$name/$key"
                
                # Save to temp file
                local temp_file="$temp_dir/${namespace}_${name}_${key}"
                kubectl get secret -n "$namespace" "$name" -o jsonpath="{.data['$key']}" | base64 -d > "$temp_file"
                
                trust_stores+=("$temp_file")
            fi
        done
    done
    
    # Process found trust stores
    for file in "${trust_stores[@]}"; do
        process_trust_store "$file"
    done
    
    # Clean up
    rm -rf "$temp_dir"
}

# Scan Docker containers for trust stores
scan_docker() {
    log_info "Scanning Docker containers for trust stores"
    
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        log_error "docker command not found, cannot scan Docker containers"
        return 1
    fi
    
    local temp_dir=$(mktemp -d)
    
    # Get list of running containers
    docker ps --format "{{.ID}}" | while read -r container_id; do
        log_debug "Scanning Docker container: $container_id"
        
        # Common trust store locations in containers
        local locations=(
            "/etc/ssl/certs"
            "/usr/local/share/ca-certificates"
            "/etc/pki/tls/certs"
            "/etc/pki/ca-trust/source/anchors"
            "/opt/java/openjdk/lib/security"
            "/usr/lib/jvm/*/jre/lib/security"
        )
        
        for location in "${locations[@]}"; do
            # Check if path exists in container
            if docker exec "$container_id" ls -la "$location" &>/dev/null; then
                log_debug "Found trust store location in container $container_id: $location"
                
                # Find trust store files
                docker exec "$container_id" find "$location" -type f \( -name "*.jks" -o -name "*.keystore" -o -name "*.truststore" -o -name "*.p12" -o -name "*.pfx" -o -name "*.pem" -o -name "*.crt" -o -name "*.cer" -o -name "*.cert" -o -name "cacerts" \) 2>/dev/null | while read -r file; do
                    log_info "Found trust store in container $container_id: $file"
                    
                    # Copy to temp directory
                    local temp_file="$temp_dir/container_${container_id}_$(basename "$file")"
                    docker cp "$container_id:$file" "$temp_file"
                    
                    # Process the trust store
                    if process_trust_store "$temp_file"; then
                        # Copy back to container if successful
                        docker cp "$temp_file" "$container_id:$file"
                        log_success "Updated trust store in container $container_id: $file"
                        
                        # Restart container if requested
                        if [ "$RESTART_SERVICES" = true ]; then
                            log_info "Restarting container $container_id"
                            docker restart "$container_id"
                        fi
                    fi
                done
            fi
        done
    done
    
    # Clean up
    rm -rf "$temp_dir"
}

# Process a single trust store file
process_trust_store() {
    local file="$1"
    local file_type=$(detect_file_type "$file")
    local result=false
    
    log_info "Processing trust store: $file (Type: $file_type)"
    
    # If baseline store is provided, compare first
    if [ -n "$BASELINE_URL" ]; then
        compare_trust_stores "$file"
        if [ "$COMPARE_MODE" = true ]; then
            return $?
        fi
    fi
    
    # Continue with existing processing if not in compare-only mode
    case "$file_type" in
        "JKS")
            handle_jks "$file"
            result=$?
            ;;
        "PKCS12")
            handle_pkcs12 "$file"
            result=$?
            ;;
        "PEM")
            handle_pem "$file"
            result=$?
            ;;
        "UNKNOWN")
            log_warning "Unknown file type for $file, skipping"
            ;;
    esac
    
    return $result
}

# Restart services if needed
restart_affected_services() {
    if [ "$RESTART_SERVICES" = true ]; then
        log_info "Checking for services that need to be restarted"
        
        # Check for common services
        for service in tomcat apache2 httpd nginx wildfly jboss; do
            if systemctl is-active --quiet "$service"; then
                log_info "Restarting service: $service"
                systemctl restart "$service"
                if [ $? -eq 0 ]; then
                    log_success "Successfully restarted $service"
                else
                    log_error "Failed to restart $service"
                fi
            fi
        done
    fi
}

# Print summary
print_summary() {
    echo
    echo "======== Trust Store Scan Summary ========"
    echo "Total successful operations: $SUMMARY_SUCCESS"
    echo "Total failed operations: $SUMMARY_FAILURE"
    echo "Log file: $LOG_FILE"
    echo "=========================================="
}

# Main function
main() {
    # Initialize log file
    echo "Trust Store Scan Log - $(date)" > "$LOG_FILE"
    echo "Command: $0 $*" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check dependencies
    check_dependencies
    
    # Scan for trust stores
    if [ "$KUBERNETES_MODE" = true ]; then
        scan_kubernetes
    elif [ "$DOCKER_MODE" = true ]; then
        scan_docker
    else
        # Scan directory for trust stores
        while IFS= read -r file; do
            process_trust_store "$file"
        done < <(scan_directory "$TARGET_DIR")
    fi
    
    # Restart services if needed
    restart_affected_services
    
    # Print summary
    print_summary
}

# Run main function
main "$@"

# Add new functions after the check_dependencies function

# Download baseline trust store
download_baseline_store() {
    log_info "Downloading baseline trust store from $BASELINE_URL"
    
    # Check if wget or curl is available
    if command -v wget &> /dev/null; then
        if wget -q "$BASELINE_URL" -O "$BASELINE_STORE"; then
            log_success "Successfully downloaded baseline trust store using wget"
            return 0
        fi
    elif command -v curl &> /dev/null; then
        if curl -s "$BASELINE_URL" -o "$BASELINE_STORE"; then
            log_success "Successfully downloaded baseline trust store using curl"
            return 0
        fi
    else
        log_error "Neither wget nor curl is available"
        return 1
    fi
    
    log_error "Failed to download baseline trust store"
    return 1
}

# Compare trust stores
compare_trust_stores() {
    local file="$1"
    local file_type=$(detect_file_type "$file")
    local temp_baseline="/tmp/baseline_$(date +%s).pem"
    local temp_target="/tmp/target_$(date +%s).pem"
    local missing_certs=0
    local temp_cert="/tmp/missing_cert_$(date +%s).pem"
    local alias_prefix="added-cert-$(date +%s)"
    local alias_counter=0
    
    log_info "Comparing trust store: $file with baseline"
    
    # Convert baseline to PEM format if needed
    case $(detect_file_type "$BASELINE_STORE") in
        "JKS")
            for password in "${COMMON_PASSWORDS[@]}"; do
                if keytool -exportcert -keystore "$BASELINE_STORE" -storepass "$password" -rfc > "$temp_baseline" 2>/dev/null; then
                    break
                fi
            done
            ;;
        "PKCS12")
            for password in "${COMMON_PASSWORDS[@]}"; do
                if openssl pkcs12 -in "$BASELINE_STORE" -nokeys -passin "pass:$password" -out "$temp_baseline" 2>/dev/null; then
                    break
                fi
            done
            ;;
        "PEM")
            cp "$BASELINE_STORE" "$temp_baseline"
            ;;
        *)
            log_error "Unknown baseline trust store format"
            return 1
            ;;
    esac
    
    # Convert target to PEM format for comparison
    case "$file_type" in
        "JKS")
            for password in "${COMMON_PASSWORDS[@]}"; do
                if keytool -exportcert -keystore "$file" -storepass "$password" -rfc > "$temp_target" 2>/dev/null; then
                    export STORE_PASSWORD="$password"  # Save password for later use
                    break
                fi
            done
            ;;
        "PKCS12")
            for password in "${COMMON_PASSWORDS[@]}"; do
                if openssl pkcs12 -in "$file" -nokeys -passin "pass:$password" -out "$temp_target" 2>/dev/null; then
                    export STORE_PASSWORD="$password"  # Save password for later use
                    break
                fi
            done
            ;;
        "PEM")
            cp "$file" "$temp_target"
            ;;
        *)
            log_error "Unknown target trust store format"
            return 1
            ;;
    esac
    
    # Extract individual certificates from both files
    local baseline_dir=$(mktemp -d)
    local target_dir=$(mktemp -d)
    
    # Split baseline certificates
    csplit -z -f "$baseline_dir/cert-" "$temp_baseline" '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null
    
    # Split target certificates
    csplit -z -f "$target_dir/cert-" "$temp_target" '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null
    
    # Compare certificates
    local total_baseline=$(find "$baseline_dir" -type f | wc -l)
    local total_target=$(find "$target_dir" -type f | wc -l)
    
    log_info "Baseline contains $total_baseline certificates"
    log_info "Target contains $total_target certificates"
    
    # Check for missing certificates
    for baseline_cert in "$baseline_dir"/cert-*; do
        local found=false
        for target_cert in "$target_dir"/cert-*; do
            if openssl x509 -fingerprint -noout -in "$baseline_cert" 2>/dev/null | \
               cmp -s - <(openssl x509 -fingerprint -noout -in "$target_cert" 2>/dev/null); then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            ((missing_certs++))
            local subject=$(openssl x509 -noout -subject -in "$baseline_cert" 2>/dev/null)
            log_warning "Missing certificate: $subject"
            
            if [ "$COMPARE_MODE" = false ]; then
                log_info "Adding missing certificate to $file"
                
                # Handle different store types differently
                case "$file_type" in
                    "JKS")
                        # For JKS, we use keytool to import
                        cp "$baseline_cert" "$temp_cert"
                        keytool -importcert -noprompt -keystore "$file" \
                            -storepass "$STORE_PASSWORD" \
                            -alias "${alias_prefix}-${alias_counter}" \
                            -file "$temp_cert"
                        ;;
                    "PKCS12")
                        # For PKCS12, we convert and merge
                        cp "$baseline_cert" "$temp_cert"
                        local temp_pkcs12="/tmp/temp_pkcs12_$(date +%s).p12"
                        openssl pkcs12 -export -in "$temp_cert" -nokeys \
                            -passout "pass:$STORE_PASSWORD" \
                            -out "$temp_pkcs12"
                        if openssl pkcs12 -in "$file" -nokeys -passin "pass:$STORE_PASSWORD" \
                            -passout "pass:$STORE_PASSWORD" -out "$file.tmp" &>/dev/null; then
                            cat "$temp_pkcs12" >> "$file.tmp"
                            mv "$file.tmp" "$file"
                            log_success "Successfully added certificate to PKCS12"
                        fi
                        rm -f "$temp_pkcs12"
                        ;;
                    "PEM")
                        # For PEM, simple append
                        cat "$baseline_cert" >> "$file"
                        ;;
                esac
            fi
        fi
    done
    
    # Clean up
    rm -f "$temp_baseline" "$temp_target" "$temp_cert"
    rm -rf "$baseline_dir" "$target_dir"
    unset STORE_PASSWORD
    
    if [ $missing_certs -eq 0 ]; then
        log_success "Trust store $file contains all baseline certificates"
        return 0
    else
        log_warning "Trust store $file is missing $missing_certs certificates"
        return 1
    fi
}

# Find keytool from JRE installations
find_keytool() {
    local keytool_path=""
    
    # Common JRE/JDK installation directories
    local java_dirs=(
        "/usr/lib/jvm"              # Linux default
        "/usr/java"                 # Alternative Linux
        "/usr/local/java"           # Local installations
        "/Library/Java/JavaVirtualMachines"  # macOS
        "/System/Library/Java/JavaVirtualMachines"  # macOS System
        "/opt/java"                 # Optional installations
        "/opt/jdk"
        "/opt/openjdk"
        "$HOME/.sdkman/candidates/java"  # SDKMAN installations
        "/c/Program Files/Java"     # Windows (through WSL)
        "/c/Program Files (x86)/Java"
    )
    
    log_info "Searching for keytool utility..."
    
    # First check if keytool is already in PATH
    if command -v keytool &> /dev/null; then
        keytool_path=$(command -v keytool)
        log_success "Found keytool in PATH: $keytool_path"
        echo "$keytool_path"
        return 0
    fi
    
    # Search in common Java directories
    for base_dir in "${java_dirs[@]}"; do
        if [ -d "$base_dir" ]; then
            log_debug "Searching in $base_dir"
            # Find all keytool executables
            while IFS= read -r path; do
                if [ -x "$path" ]; then
                    log_success "Found keytool: $path"
                    echo "$path"
                    return 0
                fi
            done < <(find "$base_dir" -type f -name "keytool" 2>/dev/null)
        fi
    done
    
    # If no keytool found, try to help user install Java
    log_error "Could not find keytool utility"
    log_info "Please install Java Runtime Environment (JRE) or Java Development Kit (JDK)"
    log_info "You can install Java using one of these methods:"
    log_info "- macOS: brew install openjdk"
    log_info "- Ubuntu/Debian: sudo apt-get install default-jre"
    log_info "- CentOS/RHEL: sudo yum install java-11-openjdk"
    log_info "- Manual download: https://adoptium.net/temurin/releases/"
    
    return 1
} 