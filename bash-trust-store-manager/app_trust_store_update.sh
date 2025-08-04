#!/bin/bash

# Script to update application-specific trust stores
# This script handles trust store updates for various application frameworks
# including Node.js, Python, Ruby, Go, and .NET applications

set -e

# Display usage information
usage() {
    echo "Usage: $0 -s <standard_trust_store> [-d <app_directory>] [-m <mode>] [-u <url>] [-h]"
    echo "  -s  Path to the standard trust store (PEM file)"
    echo "  -d  Directory to search for applications (default: current directory)"
    echo "  -m  Mode of operation (default: 2)"
    echo "      1: Compare and log differences only"
    echo "      2: Update application configurations"
    echo "      3: Force update all configurations"
    echo "  -u  URL to download standard trust store (instead of using -s)"
    echo "  -h  Display this help message"
    exit 1
}

# Default values
APP_DIR="."
STANDARD_TRUST_STORE=""
TRUST_STORE_URL=""
MODE=2  # Default mode: update configurations

# Parse command line arguments
while getopts "s:d:m:u:h" opt; do
    case $opt in
        s) STANDARD_TRUST_STORE="$OPTARG" ;;
        d) APP_DIR="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        u) TRUST_STORE_URL="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Check if URL is provided for trust store download
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Downloading standard trust store from URL: $TRUST_STORE_URL"
    DOWNLOADED_TRUST_STORE="$TEMP_DIR/downloaded_trust_store.pem"
    
    # Check if curl or wget is available
    if command -v curl &> /dev/null; then
        if ! curl -s -o "$DOWNLOADED_TRUST_STORE" "$TRUST_STORE_URL"; then
            echo "Error: Failed to download trust store from $TRUST_STORE_URL"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -q -O "$DOWNLOADED_TRUST_STORE" "$TRUST_STORE_URL"; then
            echo "Error: Failed to download trust store from $TRUST_STORE_URL"
            exit 1
        fi
    else
        echo "Error: Neither curl nor wget is available. Cannot download trust store."
        exit 1
    fi
    
    # Check if the downloaded file contains certificates
    if ! grep -q "BEGIN CERTIFICATE" "$DOWNLOADED_TRUST_STORE"; then
        echo "Error: Downloaded file does not contain certificates"
        exit 1
    fi
    
    STANDARD_TRUST_STORE="$DOWNLOADED_TRUST_STORE"
    echo "Successfully downloaded trust store"
fi

# Check if standard trust store is provided
if [ -z "$STANDARD_TRUST_STORE" ]; then
    echo "Error: Standard trust store file (-s) or URL (-u) is required"
    usage
fi

# Check if standard trust store exists (only if it's a file path, not a downloaded file)
if [ -z "$TRUST_STORE_URL" ] && [ ! -f "$STANDARD_TRUST_STORE" ]; then
    echo "Error: Standard trust store file '$STANDARD_TRUST_STORE' does not exist"
    exit 1
fi

# Validate mode
if [[ ! "$MODE" =~ ^[1-3]$ ]]; then
    echo "Error: Invalid mode '$MODE'. Mode must be 1, 2, or 3."
    usage
fi

# Create a log file
LOG_FILE="app_trust_store_update_$(date +%Y%m%d_%H%M%S).log"
COMMANDS_FILE="fix_app_trust_store_$(date +%Y%m%d_%H%M%S).sh"
echo "Logging results to: $LOG_FILE"
echo "Fix commands will be saved to: $COMMANDS_FILE"
echo "Application Trust Store Update Report - $(date)" > "$LOG_FILE"
echo "Standard trust store: $STANDARD_TRUST_STORE" >> "$LOG_FILE"
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Trust store source: Downloaded from $TRUST_STORE_URL" >> "$LOG_FILE"
fi
echo "Mode: $([ "$MODE" -eq 1 ] && echo "Compare and log" || [ "$MODE" -eq 2 ] && echo "Update configurations" || echo "Force update all")" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"

# Create commands file header
echo "#!/bin/bash" > "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "# Commands to fix application trust stores - generated on $(date)" >> "$COMMANDS_FILE"
echo "# Run this script to apply the fixes identified by app_trust_store_update.sh" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "set -e" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "STANDARD_TRUST_STORE=\"$STANDARD_TRUST_STORE\"" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"

# Function to update Node.js trust stores
update_nodejs_trust_stores() {
    echo "Searching for Node.js applications..."
    echo "Searching for Node.js applications..." >> "$LOG_FILE"
    
    # Find package.json files to locate Node.js applications
    find "$APP_DIR" -name "package.json" | while read -r package_file; do
        app_dir=$(dirname "$package_file")
        echo "Found Node.js application in: $app_dir"
        echo "Found Node.js application in: $app_dir" >> "$LOG_FILE"
        
        # Check if .env file exists
        env_file="$app_dir/.env"
        needs_update=false
        
        if [ -f "$env_file" ]; then
            # Check if NODE_EXTRA_CA_CERTS is already set
            if grep -q "NODE_EXTRA_CA_CERTS" "$env_file"; then
                current_value=$(grep "NODE_EXTRA_CA_CERTS" "$env_file" | cut -d= -f2)
                echo "  Current NODE_EXTRA_CA_CERTS: $current_value" >> "$LOG_FILE"
                
                if [ "$current_value" != "$STANDARD_TRUST_STORE" ] || [ "$MODE" -eq 3 ]; then
                    needs_update=true
                fi
            else
                needs_update=true
            fi
        else
            needs_update=true
        fi
        
        if [ "$MODE" -eq 1 ]; then
            # Compare and log only
            if [ "$needs_update" = true ]; then
                echo "  Node.js application needs trust store update" >> "$LOG_FILE"
                echo "  Node.js application needs trust store update"
                
                # Add fix commands to the commands file
                echo "" >> "$COMMANDS_FILE"
                echo "# Fix for Node.js application in: $app_dir" >> "$COMMANDS_FILE"
                echo "echo \"Updating Node.js trust store for $app_dir...\"" >> "$COMMANDS_FILE"
                
                if [ -f "$env_file" ]; then
                    echo "# Update existing .env file" >> "$COMMANDS_FILE"
                    echo "if grep -q \"NODE_EXTRA_CA_CERTS\" \"$env_file\"; then" >> "$COMMANDS_FILE"
                    echo "    sed -i \"s|NODE_EXTRA_CA_CERTS=.*|NODE_EXTRA_CA_CERTS=\$STANDARD_TRUST_STORE|g\" \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "else" >> "$COMMANDS_FILE"
                    echo "    echo \"NODE_EXTRA_CA_CERTS=\$STANDARD_TRUST_STORE\" >> \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "fi" >> "$COMMANDS_FILE"
                else
                    echo "# Create new .env file" >> "$COMMANDS_FILE"
                    echo "echo \"NODE_EXTRA_CA_CERTS=\$STANDARD_TRUST_STORE\" > \"$env_file\"" >> "$COMMANDS_FILE"
                fi
                
                echo "echo \"Updated Node.js trust store configuration for $app_dir\"" >> "$COMMANDS_FILE"
                echo "" >> "$COMMANDS_FILE"
            else
                echo "  Node.js application trust store is up to date" >> "$LOG_FILE"
                echo "  Node.js application trust store is up to date"
            fi
        elif [ "$MODE" -eq 2 ] || [ "$MODE" -eq 3 ]; then
            # Update configurations
            if [ "$needs_update" = true ]; then
                echo "  Updating Node.js trust store configuration..."
                
                if [ -f "$env_file" ]; then
                    # Update existing .env file
                    if grep -q "NODE_EXTRA_CA_CERTS" "$env_file"; then
                        sed -i "s|NODE_EXTRA_CA_CERTS=.*|NODE_EXTRA_CA_CERTS=$STANDARD_TRUST_STORE|g" "$env_file"
                    else
                        echo "NODE_EXTRA_CA_CERTS=$STANDARD_TRUST_STORE" >> "$env_file"
                    fi
                else
                    # Create new .env file
                    echo "NODE_EXTRA_CA_CERTS=$STANDARD_TRUST_STORE" > "$env_file"
                fi
                
                echo "  Updated Node.js trust store configuration for $app_dir" >> "$LOG_FILE"
                echo "  Updated Node.js trust store configuration for $app_dir"
            else
                echo "  Node.js application trust store is up to date" >> "$LOG_FILE"
                echo "  Node.js application trust store is up to date"
            fi
        fi
        
        echo "----------------------------------------" >> "$LOG_FILE"
    done
}

# Function to update Python trust stores
update_python_trust_stores() {
    echo "Searching for Python applications..."
    echo "Searching for Python applications..." >> "$LOG_FILE"
    
    # Find requirements.txt or setup.py files to locate Python applications
    find "$APP_DIR" \( -name "requirements.txt" -o -name "setup.py" \) | while read -r python_file; do
        app_dir=$(dirname "$python_file")
        echo "Found Python application in: $app_dir"
        echo "Found Python application in: $app_dir" >> "$LOG_FILE"
        
        # Check if .env file exists
        env_file="$app_dir/.env"
        needs_update=false
        
        if [ -f "$env_file" ]; then
            # Check if SSL_CERT_FILE is already set
            if grep -q "SSL_CERT_FILE" "$env_file"; then
                current_value=$(grep "SSL_CERT_FILE" "$env_file" | cut -d= -f2)
                echo "  Current SSL_CERT_FILE: $current_value" >> "$LOG_FILE"
                
                if [ "$current_value" != "$STANDARD_TRUST_STORE" ] || [ "$MODE" -eq 3 ]; then
                    needs_update=true
                fi
            else
                needs_update=true
            fi
        else
            needs_update=true
        fi
        
        if [ "$MODE" -eq 1 ]; then
            # Compare and log only
            if [ "$needs_update" = true ]; then
                echo "  Python application needs trust store update" >> "$LOG_FILE"
                echo "  Python application needs trust store update"
                
                # Add fix commands to the commands file
                echo "" >> "$COMMANDS_FILE"
                echo "# Fix for Python application in: $app_dir" >> "$COMMANDS_FILE"
                echo "echo \"Updating Python trust store for $app_dir...\"" >> "$COMMANDS_FILE"
                
                if [ -f "$env_file" ]; then
                    echo "# Update existing .env file" >> "$COMMANDS_FILE"
                    echo "if grep -q \"SSL_CERT_FILE\" \"$env_file\"; then" >> "$COMMANDS_FILE"
                    echo "    sed -i \"s|SSL_CERT_FILE=.*|SSL_CERT_FILE=\$STANDARD_TRUST_STORE|g\" \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "else" >> "$COMMANDS_FILE"
                    echo "    echo \"SSL_CERT_FILE=\$STANDARD_TRUST_STORE\" >> \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "fi" >> "$COMMANDS_FILE"
                else
                    echo "# Create new .env file" >> "$COMMANDS_FILE"
                    echo "echo \"SSL_CERT_FILE=\$STANDARD_TRUST_STORE\" > \"$env_file\"" >> "$COMMANDS_FILE"
                fi
                
                echo "echo \"Updated Python trust store configuration for $app_dir\"" >> "$COMMANDS_FILE"
                echo "" >> "$COMMANDS_FILE"
            else
                echo "  Python application trust store is up to date" >> "$LOG_FILE"
                echo "  Python application trust store is up to date"
            fi
        elif [ "$MODE" -eq 2 ] || [ "$MODE" -eq 3 ]; then
            # Update configurations
            if [ "$needs_update" = true ]; then
                echo "  Updating Python trust store configuration..."
                
                if [ -f "$env_file" ]; then
                    # Update existing .env file
                    if grep -q "SSL_CERT_FILE" "$env_file"; then
                        sed -i "s|SSL_CERT_FILE=.*|SSL_CERT_FILE=$STANDARD_TRUST_STORE|g" "$env_file"
                    else
                        echo "SSL_CERT_FILE=$STANDARD_TRUST_STORE" >> "$env_file"
                    fi
                else
                    # Create new .env file
                    echo "SSL_CERT_FILE=$STANDARD_TRUST_STORE" > "$env_file"
                fi
                
                echo "  Updated Python trust store configuration for $app_dir" >> "$LOG_FILE"
                echo "  Updated Python trust store configuration for $app_dir"
            else
                echo "  Python application trust store is up to date" >> "$LOG_FILE"
                echo "  Python application trust store is up to date"
            fi
        fi
        
        echo "----------------------------------------" >> "$LOG_FILE"
    done
}

# Function to update Ruby trust stores
update_ruby_trust_stores() {
    echo "Searching for Ruby applications..."
    echo "Searching for Ruby applications..." >> "$LOG_FILE"
    
    # Find Gemfile files to locate Ruby applications
    find "$APP_DIR" -name "Gemfile" | while read -r gemfile; do
        app_dir=$(dirname "$gemfile")
        echo "Found Ruby application in: $app_dir"
        echo "Found Ruby application in: $app_dir" >> "$LOG_FILE"
        
        # Check if .env file exists
        env_file="$app_dir/.env"
        needs_update=false
        
        if [ -f "$env_file" ]; then
            # Check if SSL_CERT_FILE is already set
            if grep -q "SSL_CERT_FILE" "$env_file"; then
                current_value=$(grep "SSL_CERT_FILE" "$env_file" | cut -d= -f2)
                echo "  Current SSL_CERT_FILE: $current_value" >> "$LOG_FILE"
                
                if [ "$current_value" != "$STANDARD_TRUST_STORE" ] || [ "$MODE" -eq 3 ]; then
                    needs_update=true
                fi
            else
                needs_update=true
            fi
        else
            needs_update=true
        fi
        
        if [ "$MODE" -eq 1 ]; then
            # Compare and log only
            if [ "$needs_update" = true ]; then
                echo "  Ruby application needs trust store update" >> "$LOG_FILE"
                echo "  Ruby application needs trust store update"
                
                # Add fix commands to the commands file
                echo "" >> "$COMMANDS_FILE"
                echo "# Fix for Ruby application in: $app_dir" >> "$COMMANDS_FILE"
                echo "echo \"Updating Ruby trust store for $app_dir...\"" >> "$COMMANDS_FILE"
                
                if [ -f "$env_file" ]; then
                    echo "# Update existing .env file" >> "$COMMANDS_FILE"
                    echo "if grep -q \"SSL_CERT_FILE\" \"$env_file\"; then" >> "$COMMANDS_FILE"
                    echo "    sed -i \"s|SSL_CERT_FILE=.*|SSL_CERT_FILE=\$STANDARD_TRUST_STORE|g\" \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "else" >> "$COMMANDS_FILE"
                    echo "    echo \"SSL_CERT_FILE=\$STANDARD_TRUST_STORE\" >> \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "fi" >> "$COMMANDS_FILE"
                else
                    echo "# Create new .env file" >> "$COMMANDS_FILE"
                    echo "echo \"SSL_CERT_FILE=\$STANDARD_TRUST_STORE\" > \"$env_file\"" >> "$COMMANDS_FILE"
                fi
                
                echo "echo \"Updated Ruby trust store configuration for $app_dir\"" >> "$COMMANDS_FILE"
                echo "" >> "$COMMANDS_FILE"
            else
                echo "  Ruby application trust store is up to date" >> "$LOG_FILE"
                echo "  Ruby application trust store is up to date"
            fi
        elif [ "$MODE" -eq 2 ] || [ "$MODE" -eq 3 ]; then
            # Update configurations
            if [ "$needs_update" = true ]; then
                echo "  Updating Ruby trust store configuration..."
                
                if [ -f "$env_file" ]; then
                    # Update existing .env file
                    if grep -q "SSL_CERT_FILE" "$env_file"; then
                        sed -i "s|SSL_CERT_FILE=.*|SSL_CERT_FILE=$STANDARD_TRUST_STORE|g" "$env_file"
                    else
                        echo "SSL_CERT_FILE=$STANDARD_TRUST_STORE" >> "$env_file"
                    fi
                else
                    # Create new .env file
                    echo "SSL_CERT_FILE=$STANDARD_TRUST_STORE" > "$env_file"
                fi
                
                echo "  Updated Ruby trust store configuration for $app_dir" >> "$LOG_FILE"
                echo "  Updated Ruby trust store configuration for $app_dir"
            else
                echo "  Ruby application trust store is up to date" >> "$LOG_FILE"
                echo "  Ruby application trust store is up to date"
            fi
        fi
        
        echo "----------------------------------------" >> "$LOG_FILE"
    done
}

# Function to update Go trust stores
update_go_trust_stores() {
    echo "Searching for Go applications..."
    echo "Searching for Go applications..." >> "$LOG_FILE"
    
    # Find go.mod files to locate Go applications
    find "$APP_DIR" -name "go.mod" | while read -r gomod; do
        app_dir=$(dirname "$gomod")
        echo "Found Go application in: $app_dir"
        echo "Found Go application in: $app_dir" >> "$LOG_FILE"
        
        # Check if .env file exists
        env_file="$app_dir/.env"
        needs_update=false
        
        if [ -f "$env_file" ]; then
            # Check if SSL_CERT_FILE is already set
            if grep -q "SSL_CERT_FILE" "$env_file"; then
                current_value=$(grep "SSL_CERT_FILE" "$env_file" | cut -d= -f2)
                echo "  Current SSL_CERT_FILE: $current_value" >> "$LOG_FILE"
                
                if [ "$current_value" != "$STANDARD_TRUST_STORE" ] || [ "$MODE" -eq 3 ]; then
                    needs_update=true
                fi
            else
                needs_update=true
            fi
        else
            needs_update=true
        fi
        
        if [ "$MODE" -eq 1 ]; then
            # Compare and log only
            if [ "$needs_update" = true ]; then
                echo "  Go application needs trust store update" >> "$LOG_FILE"
                echo "  Go application needs trust store update"
                
                # Add fix commands to the commands file
                echo "" >> "$COMMANDS_FILE"
                echo "# Fix for Go application in: $app_dir" >> "$COMMANDS_FILE"
                echo "echo \"Updating Go trust store for $app_dir...\"" >> "$COMMANDS_FILE"
                
                if [ -f "$env_file" ]; then
                    echo "# Update existing .env file" >> "$COMMANDS_FILE"
                    echo "if grep -q \"SSL_CERT_FILE\" \"$env_file\"; then" >> "$COMMANDS_FILE"
                    echo "    sed -i \"s|SSL_CERT_FILE=.*|SSL_CERT_FILE=\$STANDARD_TRUST_STORE|g\" \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "else" >> "$COMMANDS_FILE"
                    echo "    echo \"SSL_CERT_FILE=\$STANDARD_TRUST_STORE\" >> \"$env_file\"" >> "$COMMANDS_FILE"
                    echo "fi" >> "$COMMANDS_FILE"
                else
                    echo "# Create new .env file" >> "$COMMANDS_FILE"
                    echo "echo \"SSL_CERT_FILE=\$STANDARD_TRUST_STORE\" > \"$env_file\"" >> "$COMMANDS_FILE"
                fi
                
                echo "echo \"Updated Go trust store configuration for $app_dir\"" >> "$COMMANDS_FILE"
                echo "" >> "$COMMANDS_FILE"
            else
                echo "  Go application trust store is up to date" >> "$LOG_FILE"
                echo "  Go application trust store is up to date"
            fi
        elif [ "$MODE" -eq 2 ] || [ "$MODE" -eq 3 ]; then
            # Update configurations
            if [ "$needs_update" = true ]; then
                echo "  Updating Go trust store configuration..."
                
                if [ -f "$env_file" ]; then
                    # Update existing .env file
                    if grep -q "SSL_CERT_FILE" "$env_file"; then
                        sed -i "s|SSL_CERT_FILE=.*|SSL_CERT_FILE=$STANDARD_TRUST_STORE|g" "$env_file"
                    else
                        echo "SSL_CERT_FILE=$STANDARD_TRUST_STORE" >> "$env_file"
                    fi
                else
                    # Create new .env file
                    echo "SSL_CERT_FILE=$STANDARD_TRUST_STORE" > "$env_file"
                fi
                
                echo "  Updated Go trust store configuration for $app_dir" >> "$LOG_FILE"
                echo "  Updated Go trust store configuration for $app_dir"
            else
                echo "  Go application trust store is up to date" >> "$LOG_FILE"
                echo "  Go application trust store is up to date"
            fi
        fi
        
        echo "----------------------------------------" >> "$LOG_FILE"
    done
}

# Function to update .NET trust stores
update_dotnet_trust_stores() {
    echo "Searching for .NET applications..."
    echo "Searching for .NET applications..." >> "$LOG_FILE"
    
    # Find .csproj files to locate .NET applications
    find "$APP_DIR" -name "*.csproj" | while read -r csproj; do
        app_dir=$(dirname "$csproj")
        echo "Found .NET application in: $app_dir"
        echo "Found .NET application in: $app_dir" >> "$LOG_FILE"
        
        # Check if appsettings.json exists
        settings_file="$app_dir/appsettings.json"
        needs_update=false
        
        if [ -f "$settings_file" ]; then
            # Check if certificate path is already set
            if grep -q "CertificatePath" "$settings_file"; then
                # This is a simplistic check - in a real scenario, you'd use a JSON parser
                echo "  appsettings.json already contains certificate configuration" >> "$LOG_FILE"
                
                if [ "$MODE" -eq 3 ]; then
                    needs_update=true
                fi
            else
                needs_update=true
            fi
        else
            # Create a basic appsettings.json if it doesn't exist
            needs_update=true
        fi
        
        if [ "$MODE" -eq 1 ]; then
            # Compare and log only
            if [ "$needs_update" = true ]; then
                echo "  .NET application needs trust store update" >> "$LOG_FILE"
                echo "  .NET application needs trust store update"
                
                # Add fix commands to the commands file
                echo "" >> "$COMMANDS_FILE"
                echo "# Fix for .NET application in: $app_dir" >> "$COMMANDS_FILE"
                echo "echo \"Updating .NET trust store for $app_dir...\"" >> "$COMMANDS_FILE"
                
                if [ -f "$settings_file" ]; then
                    echo "# Update existing appsettings.json file" >> "$COMMANDS_FILE"
                    echo "# Note: This is a simplistic approach. In a real scenario, use a JSON parser" >> "$COMMANDS_FILE"
                    echo "if grep -q \"CertificatePath\" \"$settings_file\"; then" >> "$COMMANDS_FILE"
                    echo "    # Replace existing certificate path - this is a simplistic approach" >> "$COMMANDS_FILE"
                    echo "    sed -i 's|\"CertificatePath\": \".*\"|\"CertificatePath\": \"\$STANDARD_TRUST_STORE\"|g' \"$settings_file\"" >> "$COMMANDS_FILE"
                    echo "else" >> "$COMMANDS_FILE"
                    echo "    # Add certificate configuration - this is a simplistic approach" >> "$COMMANDS_FILE"
                    echo "    sed -i 's|{|{\\n  \"Certificates\": {\\n    \"CertificatePath\": \"\$STANDARD_TRUST_STORE\"\\n  },|' \"$settings_file\"" >> "$COMMANDS_FILE"
                    echo "fi" >> "$COMMANDS_FILE"
                else
                    echo "# Create new appsettings.json file" >> "$COMMANDS_FILE"
                    echo "cat > \"$settings_file\" << 'EOF'" >> "$COMMANDS_FILE"
                    echo "{" >> "$COMMANDS_FILE"
                    echo "  \"Certificates\": {" >> "$COMMANDS_FILE"
                    echo "    \"CertificatePath\": \"\$STANDARD_TRUST_STORE\"" >> "$COMMANDS_FILE"
                    echo "  }," >> "$COMMANDS_FILE"
                    echo "  \"Logging\": {" >> "$COMMANDS_FILE"
                    echo "    \"LogLevel\": {" >> "$COMMANDS_FILE"
                    echo "      \"Default\": \"Information\"" >> "$COMMANDS_FILE"
                    echo "    }" >> "$COMMANDS_FILE"
                    echo "  }" >> "$COMMANDS_FILE"
                    echo "}" >> "$COMMANDS_FILE"
                    echo "EOF" >> "$COMMANDS_FILE"
                fi
                
                echo "echo \"Updated .NET trust store configuration for $app_dir\"" >> "$COMMANDS_FILE"
                echo "" >> "$COMMANDS_FILE"
            else
                echo "  .NET application trust store is up to date" >> "$LOG_FILE"
                echo "  .NET application trust store is up to date"
            fi
        elif [ "$MODE" -eq 2 ] || [ "$MODE" -eq 3 ]; then
            # Update configurations
            if [ "$needs_update" = true ]; then
                echo "  Updating .NET trust store configuration..."
                
                if [ -f "$settings_file" ]; then
                    # Update existing appsettings.json file
                    if grep -q "CertificatePath" "$settings_file"; then
                        # Replace existing certificate path - this is a simplistic approach
                        sed -i "s|\"CertificatePath\": \".*\"|\"CertificatePath\": \"$STANDARD_TRUST_STORE\"|g" "$settings_file"
                    else
                        # Add certificate configuration - this is a simplistic approach
                        sed -i "s|{|{\\n  \"Certificates\": {\\n    \"CertificatePath\": \"$STANDARD_TRUST_STORE\"\\n  },|" "$settings_file"
                    fi
                else
                    # Create new appsettings.json file
                    cat > "$settings_file" << EOF
{
  "Certificates": {
    "CertificatePath": "$STANDARD_TRUST_STORE"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
EOF
                fi
                
                echo "  Updated .NET trust store configuration for $app_dir" >> "$LOG_FILE"
                echo "  Updated .NET trust store configuration for $app_dir"
            else
                echo "  .NET application trust store is up to date" >> "$LOG_FILE"
                echo "  .NET application trust store is up to date"
            fi
        fi
        
        echo "----------------------------------------" >> "$LOG_FILE"
    done
}

# Run the update functions
update_nodejs_trust_stores
update_python_trust_stores
update_ruby_trust_stores
update_go_trust_stores
update_dotnet_trust_stores

# Make the commands file executable
if [ "$MODE" -eq 1 ]; then
    chmod +x "$COMMANDS_FILE"
    echo "Fix commands have been saved to $COMMANDS_FILE"
    echo "Run this file to apply the fixes: ./$COMMANDS_FILE"
fi

echo "Application trust store update completed."
echo "See $LOG_FILE for details." 