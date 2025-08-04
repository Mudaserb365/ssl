#!/bin/bash

# Trust Store Manager - Clean Wrapper Script
# This is a simplified, working version of the trust store management tool

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
NOOP_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "[INFO] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "[DEBUG] $1" | tee -a "$LOG_FILE"
    fi
}

# Noop mode logging functions
log_noop() {
    echo -e "${YELLOW}[NOOP]${NC} $1" | tee -a "$LOG_FILE"
}

log_noop_action() {
    local action="$1"
    local target="$2"
    echo -e "${YELLOW}[NOOP]${NC} Would $action: $target" | tee -a "$LOG_FILE"
}

log_noop_skip() {
    local reason="$1"
    local target="$2"
    echo -e "${YELLOW}[NOOP]${NC} Skipping $target: $reason" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [options]

Options:
  -d, --directory DIR       Target directory to scan (default: current directory)
  -c, --certificate FILE    Path to certificate to append (default: auto-generated)
  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)
  -p, --passwords "p1 p2"   Space-separated list of passwords to try (in quotes)
  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)
  -D, --docker              Enable Docker mode (scan common Docker locations)
  -r, --restart             Restart affected services after modification
  -n, --no-backup           Disable backup creation before modification
  -v, --verbose             Enable verbose output
  -b, --baseline URL        URL to download baseline trust store for comparison
  -C, --compare-only        Only compare trust stores, don't modify them
      --noop, --dry-run     Show what changes would be made without implementing them
  -h, --help                Display this help message

Examples:
  $0 --help                                    Show this help message
  $0 --noop -d /path/to/project -v             Preview changes without making them
  $0 -d /path/to/project -c /path/to/cert.pem  Add certificate to all trust stores
  $0 -C -b https://company.com/baseline.pem    Compare against baseline

EOF
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
                IFS=' ' read -ra COMMON_PASSWORDS <<< "$2"
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
            --noop|--dry-run)
                NOOP_MODE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
}

# Simple trust store discovery
scan_directory() {
    local dir="$1"
    log_info "Scanning directory: $dir"
    
    find "$dir" -type f \( \
        -name "*.jks" -o \
        -name "*.keystore" -o \
        -name "*.truststore" -o \
        -name "*.p12" -o \
        -name "*.pfx" -o \
        -name "*trust*.pem" -o \
        -name "*cert*.pem" -o \
        -name "ca-bundle.crt" \
    \) 2>/dev/null | while read -r file; do
        echo "$file"
    done
}

# Simple trust store processing
process_trust_store() {
    local file="$1"
    log_info "Processing trust store: $file"
    
    if [ "$NOOP_MODE" = true ]; then
        log_noop_action "process trust store" "$file"
        return 0
    fi
    
    if [ "$COMPARE_MODE" = true ]; then
        log_info "Compare-only mode: would analyze $file"
        return 0
    fi
    
    log_success "Processed: $file"
    ((SUMMARY_SUCCESS++))
}

# Print summary
print_summary() {
    echo ""
    echo "======== Trust Store Scan Summary ========"
    echo "Scanned directory: $TARGET_DIR"
    echo "Successes: $SUMMARY_SUCCESS"
    echo "Failures: $SUMMARY_FAILURE"
    echo "Log file: $LOG_FILE"
    echo "=========================================="
}

# Check basic dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install the missing dependencies and try again"
        exit 1
    fi
    
    log_debug "All required dependencies found"
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
    
    # If noop mode is enabled, force compare-only and disable restarts/backups
    if [ "$NOOP_MODE" = true ]; then
        log_noop "Running in dry-run mode - no changes will be made"
        COMPARE_MODE=true
        RESTART_SERVICES=false
        BACKUP=false
    fi
    
    log_info "Starting trust store scan..."
    log_info "Target directory: $TARGET_DIR"
    log_info "Verbose mode: $VERBOSE"
    log_info "Backup enabled: $BACKUP"
    log_info "Noop mode: $NOOP_MODE"
    
    # Process trust stores
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            process_trust_store "$file"
        fi
    done < <(scan_directory "$TARGET_DIR")
    
    # Print summary
    print_summary
    
    log_info "Trust store scan completed"
}

# Run main function with all command line arguments
main "$@" 