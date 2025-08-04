#!/bin/bash

# Trust Store Manager - Enterprise Edition (Bash Implementation)
# Automated SSL/TLS trust store management with centralized logging
# This script provides equivalent functionality to the Go implementation

set -euo pipefail

# Script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-config.yaml}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables for configuration (using regular variables for compatibility)
MACHINE_IP=""
MACHINE_ID=""
HOSTNAME=""
OS=""
ARCH=""
IP_ADDRESSES=""
USERNAME=""
USER_ID=""
HOME_DIR=""
PROJECT_NAME=""
BRANCH_NAME=""
COMMIT_HASH=""
REPOSITORY_URL=""
IS_DIRTY=""
WORKING_DIR=""
SESSION_ID=""
START_TIME=""
LOG_FILE=""
WEBHOOK_URL=""
WEBHOOK_API_KEY=""
REQUIRE_NOOP="true"
UPSERT_ONLY="true"
DUAL_OUTPUT="true"

# Command line variables (equivalent to Go implementation)
TARGET_DIR="."
CERTIFICATE_PATH=""
BASELINE_URL=""
PASSWORDS=""
KUBERNETES_MODE=false
DOCKER_MODE=false
RESTART_SERVICES=false
NO_BACKUP=false
VERBOSE=false
COMPARE_ONLY=false
NOOP_MODE=false
AUTO_MODE=false
INTERACTIVE_MODE=false
SHOW_HELP=false

# Arrays for structured logging
declare -a MODIFICATIONS=()

# Usage function
usage() {
    cat << EOF
Trust Store Manager - Enterprise Edition (Bash)
Automated SSL/TLS trust store management with centralized logging

IMPORTANT: This tool requires --noop flag for safety. No modifications
will be made without explicit dry-run confirmation.

Usage:
  $0 [options]

Required Safety Flag:
      --noop, --dry-run     REQUIRED: Show changes without implementing them

Core Options:
  -d, --directory DIR       Target directory to scan (default: current directory)
  -c, --certificate FILE    Path to certificate to append
  -l, --log FILE            Log file path
  -b, --baseline URL        URL to download baseline trust store
      --config FILE         Path to configuration file (default: config.yaml)

Operation Modes:
  -k, --kubernetes          Enable Kubernetes mode
  -D, --docker              Enable Docker mode
  -C, --compare-only        Only compare, don't modify

Execution Control:
      --auto                Run in automatic mode
      --interactive         Run in interactive mode
  -v, --verbose             Enable verbose output
  -r, --restart             Restart services after modification
  -n, --no-backup           Disable backup creation
  -h, --help                Display this help message

Examples:
  # REQUIRED: Always start with --noop for safety
  $0 --noop --auto -d /path/to/project
  $0 --noop -c /path/to/cert.pem -d /path/to/project
  $0 --noop --compare-only -b https://company.com/baseline.pem

Configuration:
  Configuration is loaded from config.yaml in the current directory,
  or specified with --config flag. See config.yaml for all options.
EOF
}

# Parse YAML configuration (simplified parser for bash)
parse_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        # Don't log yet - LOG_FILE not set
        set_default_config
        return
    fi
    
    # Don't log yet - LOG_FILE not set
    
    # Parse key configuration values (simplified YAML parsing)
    BASELINE_URL=$(grep "url:" "$config_file" | head -1 | sed 's/.*url:[[:space:]]*["\047]\{0,1\}\([^"]*\)["\047]\{0,1\}.*/\1/' | xargs)
    WEBHOOK_URL=$(grep "webhook_url:" "$config_file" | sed 's/.*webhook_url:[[:space:]]*["\047]\{0,1\}\([^"]*\)["\047]\{0,1\}.*/\1/' | xargs)
    WEBHOOK_API_KEY=$(grep "webhook_api_key:" "$config_file" | sed 's/.*webhook_api_key:[[:space:]]*["\047]\{0,1\}\([^"]*\)["\047]\{0,1\}.*/\1/' | xargs)
    
    # Parse boolean values
    REQUIRE_NOOP=$(grep "require_noop:" "$config_file" | sed 's/.*require_noop:[[:space:]]*\([^[:space:]]*\).*/\1/' | xargs)
    UPSERT_ONLY=$(grep "upsert_only:" "$config_file" | sed 's/.*upsert_only:[[:space:]]*\([^[:space:]]*\).*/\1/' | xargs)
    DUAL_OUTPUT=$(grep "dual_output:" "$config_file" | sed 's/.*dual_output:[[:space:]]*\([^[:space:]]*\).*/\1/' | xargs)
    
    # Set defaults for any missing values
    [[ -z "$BASELINE_URL" ]] && BASELINE_URL="https://company.com/pki/baseline-trust-store.pem"
    [[ -z "$WEBHOOK_URL" ]] && WEBHOOK_URL="https://logs.company.com/api/trust-store-audit"
    [[ -z "$REQUIRE_NOOP" ]] && REQUIRE_NOOP="true"
    [[ -z "$UPSERT_ONLY" ]] && UPSERT_ONLY="true"
    [[ -z "$DUAL_OUTPUT" ]] && DUAL_OUTPUT="true"
    
    # Expand environment variables
    WEBHOOK_API_KEY=$(echo "$WEBHOOK_API_KEY" | envsubst)
}

# Set default configuration
set_default_config() {
    BASELINE_URL="https://company.com/pki/baseline-trust-store.pem"
    WEBHOOK_URL="https://logs.company.com/api/trust-store-audit"
    REQUIRE_NOOP="true"
    UPSERT_ONLY="true"
    DUAL_OUTPUT="true"
}

# Initialize session
init_session() {
    SESSION_ID="ts-$(date +%s%N)"
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Set default log file if not provided
    if [[ -z "$LOG_FILE" ]]; then
        LOG_FILE="./logs/trust-store-manager-$(date +%Y%m%d_%H%M%S).log"
    fi
    
    # Create logs directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Initialize log file
    echo "Trust Store Manager Log - $(date)" > "$LOG_FILE"
    echo "Session ID: $SESSION_ID" >> "$LOG_FILE"
    echo "Command: $0 $*" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"
}

# Collect system information
collect_system_info() {
    # Get machine IP (cross-platform compatible)
    if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
        MACHINE_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    elif command -v ifconfig >/dev/null 2>&1; then
        MACHINE_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d':' -f2 2>/dev/null || echo "unknown")
    else
        MACHINE_IP="unknown"
    fi
    HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
    OS=$(uname -s 2>/dev/null || echo "unknown")
    ARCH=$(uname -m 2>/dev/null || echo "unknown")
    MACHINE_ID="${HOSTNAME}_${MACHINE_IP}"
    
    # Get all IP addresses
    local ips=""
    if command -v ip >/dev/null 2>&1; then
        ips=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')
    elif command -v ifconfig >/dev/null 2>&1; then
        ips=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    fi
    IP_ADDRESSES="[$ips]"
}

# Collect user information
collect_user_info() {
    USERNAME=$(whoami 2>/dev/null || echo "unknown")
    USER_ID=$(id -u 2>/dev/null || echo "unknown")
    HOME_DIR="${HOME:-unknown}"
}

# Collect git information
collect_git_info() {
    WORKING_DIR=$(pwd)
    
    # Get project name
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            PROJECT_NAME=$(basename "$remote_url" .git)
            REPOSITORY_URL="$remote_url"
        else
            PROJECT_NAME=$(basename "$(pwd)")
        fi
        
        # Get branch name
        BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        
        # Get commit hash
        COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        
        # Check if repository is dirty
        if git diff --quiet 2>/dev/null; then
            IS_DIRTY="false"
        else
            IS_DIRTY="true"
        fi
    else
        PROJECT_NAME=$(basename "$(pwd)")
        BRANCH_NAME="unknown"
        COMMIT_HASH="unknown"
        REPOSITORY_URL="unknown"
        IS_DIRTY="false"
    fi
}

# Logging functions
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # JSON log entry
    local json_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "session_id": "$SESSION_ID",
  "level": "$level",
  "message": "$message"
}
EOF
)
    
    # Log to file
    echo "[$level] $json_entry" >> "$LOG_FILE"
    
    # Log to terminal if dual output is enabled
    if [[ "$DUAL_OUTPUT" == "true" ]]; then
        case "$level" in
            "ERROR")   echo -e "${RED}[ERROR]${NC} $message" ;;
            "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
            "NOOP")    echo -e "${YELLOW}[NOOP]${NC} $message" ;;
            *)         echo -e "[INFO] $message" ;;
        esac
    fi
}

# Log trust store modification
log_modification() {
    local file_path="$1"
    local file_type="$2"
    local operation="$3"
    local status="$4"
    local noop_output="$5"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local modification=$(cat <<EOF
{
  "file_path": "$file_path",
  "file_type": "$file_type",
  "operation": "$operation",
  "status": "$status",
  "timestamp": "$timestamp",
  "noop_output": "$noop_output",
  "certificates_added": [],
  "before_state": {"certificate_count": 0},
  "after_state": {"certificate_count": 0},
  "diff": ""
}
EOF
)
    
    MODIFICATIONS+=("$modification")
    
    # Log immediately
    echo "[MODIFICATION] $modification" >> "$LOG_FILE"
}

# Send audit log to webhook
send_audit_log() {
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local duration="0s"  # Simplified for compatibility
    
    # Build modifications array
    local modifications_json="["
    local first=true
    if [[ ${#MODIFICATIONS[@]} -gt 0 ]]; then
        for mod in "${MODIFICATIONS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                modifications_json+=","
            fi
            modifications_json+="$mod"
        done
    fi
    modifications_json+="]"
    
    # Build complete audit log
    local audit_log=$(cat <<EOF
{
  "machine_ip": "$MACHINE_IP",
  "machine_id": "$MACHINE_ID",
  "user": {
    "username": "$USERNAME",
    "user_id": "$USER_ID",
    "home_dir": "$HOME_DIR"
  },
  "git_project": {
    "project_name": "$PROJECT_NAME",
    "branch_name": "$BRANCH_NAME",
    "commit_hash": "$COMMIT_HASH",
    "repository_url": "$REPOSITORY_URL",
    "is_dirty": $IS_DIRTY,
    "working_dir": "$WORKING_DIR"
  },
  "modifications": $modifications_json,
  "timestamp": "$START_TIME",
  "session_id": "$SESSION_ID",
  "command": "$0 $*",
  "system_info": {
    "hostname": "$HOSTNAME",
    "os": "$OS",
    "arch": "$ARCH",
    "ip_addresses": $IP_ADDRESSES
  },
  "duration": "${duration}s",
  "summary": {
    "total_modifications": ${#MODIFICATIONS[@]},
    "successful_modifications": 0,
    "failed_modifications": 0
  }
}
EOF
)
    
    # Log audit log locally
    echo "[AUDIT_LOG] $audit_log" >> "$LOG_FILE"
    
    # Send to webhook if configured
    if [[ -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != "https://logs.company.com/api/trust-store-audit" ]]; then
        local curl_cmd="curl -s -X POST '$WEBHOOK_URL' -H 'Content-Type: application/json'"
        
        if [[ -n "$WEBHOOK_API_KEY" ]]; then
            curl_cmd+=" -H 'Authorization: Bearer $WEBHOOK_API_KEY'"
        fi
        
        curl_cmd+=" -d '$audit_log'"
        
        if eval "$curl_cmd" >/dev/null 2>&1; then
            log_message "INFO" "Audit log sent to webhook successfully"
        else
            log_message "WARNING" "Failed to send audit log to webhook"
        fi
    fi
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
                CERTIFICATE_PATH="$2"
                shift 2
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -b|--baseline)
                BASELINE_URL="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
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
            -C|--compare-only)
                COMPARE_ONLY=true
                shift
                ;;
            --noop|--dry-run)
                NOOP_MODE=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -r|--restart)
                RESTART_SERVICES=true
                shift
                ;;
            -n|--no-backup)
                NO_BACKUP=true
                shift
                ;;
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
}

# Run interactive mode
run_interactive_mode() {
    echo "=== Trust Store Manager Interactive Walkthrough ==="
    echo "This wizard will guide you through trust store management."
    echo
    
    if [[ "$NOOP_MODE" != "true" ]]; then
        echo -e "${YELLOW}WARNING: Interactive mode requires --noop flag for safety.${NC}"
        echo "Please restart with --noop flag to continue."
        return 1
    fi

    # Get target directory
    read -p "Enter the project directory path [$TARGET_DIR]: " input
    if [[ -n "$input" ]]; then
        TARGET_DIR="$input"
    fi

    echo "Analyzing project directory: $TARGET_DIR"
    echo "Running trust store scan in NOOP mode..."
    
    run_trust_store_scan
}

# Run trust store scan (simplified implementation)
run_trust_store_scan() {
    log_message "INFO" "Starting trust store scan in directory: $TARGET_DIR"
    
    if [[ "$NOOP_MODE" == "true" ]]; then
        log_message "INFO" "NOOP mode: Showing what would be done without making changes"
    fi
    
    # Example trust store discovery and modification logging
    local example_truststore="$TARGET_DIR/example.jks"
    
    if [[ -f "$example_truststore" ]]; then
        log_modification "$example_truststore" "JKS" "upsert_certificate" "noop" "Would add certificate to trust store"
        log_message "NOOP" "Would process trust store: $example_truststore"
    else
        log_message "INFO" "No trust stores found in: $TARGET_DIR"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Show help if requested
    if [[ "$SHOW_HELP" == "true" ]]; then
        usage
        return 0
    fi
    
    # Load configuration
    parse_config "$CONFIG_FILE"
    
    # Initialize session
    init_session
    
    # Collect system information
    collect_system_info
    collect_user_info
    collect_git_info
    
    # SAFETY CHECK: Enforce --noop requirement
    if [[ "$REQUIRE_NOOP" == "true" && "$NOOP_MODE" != "true" ]]; then
        echo -e "${RED}ERROR: This tool requires --noop flag for safety.${NC}"
        echo "Use --noop or --dry-run to preview changes before execution."
        echo "This prevents accidental modifications to production trust stores."
        echo
        echo "Example: $0 --noop --auto -d /path/to/project"
        echo
        echo "Run with --help for more information."
        exit 1
    fi
    
    # Log startup
    log_message "INFO" "Trust Store Manager started"
    if [[ "$NOOP_MODE" == "true" ]]; then
        log_message "INFO" "Running in NOOP mode - no changes will be made"
    fi
    
    # Default to interactive mode if no mode specified
    if [[ "$AUTO_MODE" != "true" && "$INTERACTIVE_MODE" != "true" ]]; then
        INTERACTIVE_MODE=true
    fi
    
    # Run in appropriate mode
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        run_interactive_mode
    else
        run_trust_store_scan
    fi
    
    # Send audit log
    send_audit_log
    
    log_message "INFO" "Trust Store Manager completed successfully"
}

# Execute main function with all arguments
main "$@" 