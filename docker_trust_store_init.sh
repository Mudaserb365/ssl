#!/bin/bash

# Docker initialization script for trust store management
# This script can be used as an entrypoint wrapper or in a multi-stage build
# to update trust stores in Docker containers

set -e

# Configuration - customize these variables
REPO_URL="https://github.com/Mudaserb365/ssl.git"
REPO_BRANCH="main"
TRUST_STORE_URL="https://your-central-location.com/trust-stores/standard-trust-store.pem"
JKS_TRUST_STORE_URL="https://your-central-location.com/trust-stores/standard-trust-store.jks"
JKS_PASSWORD="changeit"  # Default Java KeyStore password
SEARCH_PATHS=("/etc/pki/tls/certs" "/etc/ssl/certs" "/usr/local/share/ca-certificates")
JKS_SEARCH_PATHS=("/etc/java*/security" "/usr/lib/jvm/*/jre/lib/security")

# Function to install dependencies based on the Linux distribution
install_dependencies() {
    if [ -f /etc/alpine-release ]; then
        # Alpine Linux
        apk update
        apk add --no-cache git curl findutils openjdk11-jre-headless
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y git curl findutils default-jre-headless
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        yum update -y
        yum install -y git curl findutils java-headless
    else
        echo "Unsupported Linux distribution. Installing basic tools..."
        # Try to install with apt-get or yum
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y git curl findutils
        elif command -v yum &> /dev/null; then
            yum update -y
            yum install -y git curl findutils
        elif command -v apk &> /dev/null; then
            apk update
            apk add --no-cache git curl findutils
        else
            echo "Could not install dependencies. Please install git and curl manually."
            exit 1
        fi
    fi
}

# Create working directory
setup_environment() {
    WORK_DIR="/opt/trust-store-manager"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # Clone the repository with the scripts
    git clone --branch "$REPO_BRANCH" "$REPO_URL" .

    # Make scripts executable
    chmod +x compare_trust_stores.sh compare_jks_stores.sh docker_trust_store_update.sh

    # Create a log directory
    mkdir -p /var/log/trust-store-manager

    # Download the standard trust stores
    echo "Downloading standard trust stores..."
    curl -s -o "$WORK_DIR/standard-trust-store.pem" "$TRUST_STORE_URL"
    curl -s -o "$WORK_DIR/standard-trust-store.jks" "$JKS_TRUST_STORE_URL"
}

# Function to update PEM trust stores
update_pem_trust_stores() {
    echo "Updating PEM trust stores..."
    
    for search_path in "${SEARCH_PATHS[@]}"; do
        if [ -d "$search_path" ]; then
            echo "Searching in $search_path"
            ./compare_trust_stores.sh -s "$WORK_DIR/standard-trust-store.pem" -d "$search_path" -m 2
        fi
    done
}

# Function to update JKS trust stores
update_jks_trust_stores() {
    echo "Updating JKS trust stores..."
    
    # Try to find cacerts files
    for search_path in "${JKS_SEARCH_PATHS[@]}"; do
        if [ -d "$search_path" ]; then
            echo "Searching in $search_path"
            
            # Find all JKS files in the directory
            find "$search_path" -name "*.jks" -o -name "cacerts" | while read -r jks_file; do
                echo "Found JKS file: $jks_file"
                
                # Try with provided password
                if ./compare_jks_stores.sh -s "$WORK_DIR/standard-trust-store.jks" -d "$(dirname "$jks_file")" -p "$JKS_PASSWORD" -m 2; then
                    echo "Successfully updated $jks_file with password: $JKS_PASSWORD"
                else
                    echo "Failed to update $jks_file with password: $JKS_PASSWORD"
                    
                    # Try with empty password
                    if ./compare_jks_stores.sh -s "$WORK_DIR/standard-trust-store.jks" -d "$(dirname "$jks_file")" -p "" -m 2; then
                        echo "Successfully updated $jks_file with empty password"
                    else
                        echo "Failed to update $jks_file with empty password"
                    fi
                fi
            done
        fi
    done
}

# Main function
main() {
    echo "Starting trust store management setup..."
    
    # Install dependencies if needed
    if [ "$INSTALL_DEPS" = "true" ]; then
        install_dependencies
    fi
    
    # Set up environment
    setup_environment
    
    # Update trust stores
    update_pem_trust_stores
    update_jks_trust_stores
    
    echo "Trust store management setup completed successfully."
    
    # If there's a command to execute after setup, run it
    if [ $# -gt 0 ]; then
        echo "Executing command: $@"
        exec "$@"
    fi
}

# Run the main function with all arguments
main "$@" 