#!/bin/bash

# CloudFormation user data script to set up trust store management
# This script can be included in CloudFormation templates to automatically
# update trust stores during instance initialization

set -e

# Configuration - customize these variables
REPO_URL="https://github.com/Mudaserb365/ssl.git"
REPO_BRANCH="main"
TRUST_STORE_URL="https://your-central-location.com/trust-stores/standard-trust-store.pem"
JKS_TRUST_STORE_URL="https://your-central-location.com/trust-stores/standard-trust-store.jks"
JKS_PASSWORD="changeit"  # Default Java KeyStore password
SEARCH_PATHS=("/etc/pki/tls/certs" "/etc/ssl/certs" "/usr/local/share/ca-certificates")
JKS_SEARCH_PATHS=("/etc/java*/security" "/usr/lib/jvm/*/jre/lib/security")

# Install required packages
if command -v yum &> /dev/null; then
    # RHEL/CentOS/Amazon Linux
    yum update -y
    yum install -y git curl findutils java-headless
elif command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update
    apt-get install -y git curl findutils default-jre-headless
fi

# Create working directory
WORK_DIR="/opt/trust-store-manager"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Clone the repository with the scripts
git clone --branch "$REPO_BRANCH" "$REPO_URL" .

# Make scripts executable
chmod +x compare_trust_stores.sh compare_jks_stores.sh docker_trust_store_update.sh

# Create a log directory
mkdir -p /var/log/trust-store-manager

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

# Download the standard trust stores
echo "Downloading standard trust stores..."
curl -s -o "$WORK_DIR/standard-trust-store.pem" "$TRUST_STORE_URL"
curl -s -o "$WORK_DIR/standard-trust-store.jks" "$JKS_TRUST_STORE_URL"

# Update trust stores
update_pem_trust_stores
update_jks_trust_stores

# Create a cron job to periodically update trust stores
cat > /etc/cron.weekly/update-trust-stores << 'EOF'
#!/bin/bash
cd /opt/trust-store-manager
git pull
curl -s -o "$WORK_DIR/standard-trust-store.pem" "$TRUST_STORE_URL"
curl -s -o "$WORK_DIR/standard-trust-store.jks" "$JKS_TRUST_STORE_URL"
./compare_trust_stores.sh -s "$WORK_DIR/standard-trust-store.pem" -d "/etc/pki/tls/certs" -m 2
./compare_trust_stores.sh -s "$WORK_DIR/standard-trust-store.pem" -d "/etc/ssl/certs" -m 2
./compare_trust_stores.sh -s "$WORK_DIR/standard-trust-store.pem" -d "/usr/local/share/ca-certificates" -m 2
find /etc/java*/security /usr/lib/jvm/*/jre/lib/security -name "*.jks" -o -name "cacerts" | while read -r jks_file; do
    ./compare_jks_stores.sh -s "$WORK_DIR/standard-trust-store.jks" -d "$(dirname "$jks_file")" -p "changeit" -m 2 || \
    ./compare_jks_stores.sh -s "$WORK_DIR/standard-trust-store.jks" -d "$(dirname "$jks_file")" -p "" -m 2
done
EOF

chmod +x /etc/cron.weekly/update-trust-stores

echo "Trust store management setup completed successfully." 