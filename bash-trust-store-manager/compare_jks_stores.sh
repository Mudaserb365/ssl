#!/bin/bash

# Script to search for JKS trust stores in a project, compare with a standard trust store,
# and update them by appending trust chains from the standard store

set -e

# Display usage information
usage() {
    echo "Usage: $0 -s <standard_trust_store> [-p <password>] [-d <project_directory>] [-m <mode>] [-u <url>] [-h]"
    echo "  -s  Path to the standard trust store (JKS file)"
    echo "  -p  Password for the JKS trust stores (default: changeit)"
    echo "  -d  Directory to search for trust stores (default: current directory)"
    echo "  -m  Mode of operation (default: 2)"
    echo "      1: Compare and log differences only"
    echo "      2: Compare and append missing certificates"
    echo "      3: Compare and replace with standard trust store"
    echo "  -u  URL to download standard trust store (instead of using -s)"
    echo "  -h  Display this help message"
    exit 1
}

# Default values
PROJECT_DIR="."
STANDARD_TRUST_STORE=""
TRUST_STORE_URL=""
JKS_PASSWORD="changeit"
MODE=2  # Default mode: compare and append

# Parse command line arguments
while getopts "s:p:d:m:u:h" opt; do
    case $opt in
        s) STANDARD_TRUST_STORE="$OPTARG" ;;
        p) JKS_PASSWORD="$OPTARG" ;;
        d) PROJECT_DIR="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        u) TRUST_STORE_URL="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check if keytool is available
if ! command -v keytool &> /dev/null; then
    echo "Error: keytool is not available. Please install Java JDK or JRE."
    exit 1
fi

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Check if URL is provided for trust store download
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Downloading standard trust store from URL: $TRUST_STORE_URL"
    DOWNLOADED_TRUST_STORE="$TEMP_DIR/downloaded_trust_store.jks"
    
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
    
    # Check if the downloaded file is a valid JKS file
    if ! keytool -list -keystore "$DOWNLOADED_TRUST_STORE" -storepass "$JKS_PASSWORD" &> /dev/null; then
        echo "Error: Downloaded file is not a valid JKS trust store or password is incorrect"
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

echo "Searching for JKS trust stores in '$PROJECT_DIR'"
echo "Using standard trust store: $STANDARD_TRUST_STORE"
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Trust store source: Downloaded from $TRUST_STORE_URL"
fi
echo "Mode: $MODE - $([ "$MODE" -eq 1 ] && echo "Compare and log" || [ "$MODE" -eq 2 ] && echo "Compare and append" || echo "Compare and replace")"

# Create a log file
LOG_FILE="jks_comparison_$(date +%Y%m%d_%H%M%S).log"
COMMANDS_FILE="fix_jks_commands_$(date +%Y%m%d_%H%M%S).sh"
echo "Logging results to: $LOG_FILE"
echo "Fix commands will be saved to: $COMMANDS_FILE"
echo "JKS Trust Store Comparison Report - $(date)" > "$LOG_FILE"
echo "Standard trust store: $STANDARD_TRUST_STORE" >> "$LOG_FILE"
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Trust store source: Downloaded from $TRUST_STORE_URL" >> "$LOG_FILE"
fi
echo "Mode: $([ "$MODE" -eq 1 ] && echo "Compare and log" || [ "$MODE" -eq 2 ] && echo "Compare and append" || echo "Compare and replace")" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"

# Create commands file header
echo "#!/bin/bash" > "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "# Commands to fix JKS trust stores - generated on $(date)" >> "$COMMANDS_FILE"
echo "# Run this script to apply the fixes identified by compare_jks_stores.sh" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "set -e" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "# JKS password used for all operations" >> "$COMMANDS_FILE"
echo "JKS_PASSWORD=\"$JKS_PASSWORD\"" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"

# Extract certificates from standard trust store to a temporary directory
STANDARD_CERTS_DIR="$TEMP_DIR/standard_certs"
mkdir -p "$STANDARD_CERTS_DIR"

echo "Extracting certificates from standard trust store..."
# List all aliases in the standard trust store
STANDARD_ALIASES=$(keytool -list -keystore "$STANDARD_TRUST_STORE" -storepass "$JKS_PASSWORD" | grep "trustedCertEntry" | awk '{print $1}')
STANDARD_CERT_COUNT=$(echo "$STANDARD_ALIASES" | wc -l)
echo "Standard trust store contains $STANDARD_CERT_COUNT certificates" >> "$LOG_FILE"

# Export each certificate to a separate file
for alias in $STANDARD_ALIASES; do
    keytool -exportcert -keystore "$STANDARD_TRUST_STORE" -storepass "$JKS_PASSWORD" -alias "$alias" -file "$STANDARD_CERTS_DIR/$alias.cer" -rfc
done

# Find all JKS files in the project
find "$PROJECT_DIR" -type f -name "*.jks" | while read -r file; do
    echo "Processing: $file"
    echo "Processing: $file" >> "$LOG_FILE"
    
    # Check if file is a valid JKS file
    if keytool -list -keystore "$file" -storepass "$JKS_PASSWORD" &> /dev/null; then
        echo "  Found JKS trust store in: $file"
        
        # Create a directory for project certificates
        PROJECT_CERTS_DIR="$TEMP_DIR/project_certs"
        mkdir -p "$PROJECT_CERTS_DIR"
        rm -f "$PROJECT_CERTS_DIR"/*
        
        # List all aliases in the project trust store
        PROJECT_ALIASES=$(keytool -list -keystore "$file" -storepass "$JKS_PASSWORD" | grep "trustedCertEntry" | awk '{print $1}')
        PROJECT_CERT_COUNT=$(echo "$PROJECT_ALIASES" | wc -l)
        echo "  Project trust store contains $PROJECT_CERT_COUNT certificates" >> "$LOG_FILE"
        
        # Export each certificate to a separate file
        for alias in $PROJECT_ALIASES; do
            keytool -exportcert -keystore "$file" -storepass "$JKS_PASSWORD" -alias "$alias" -file "$PROJECT_CERTS_DIR/$alias.cer" -rfc
        done
        
        # Find missing certificates
        MISSING_COUNT=0
        MISSING_ALIASES=""
        
        for std_alias in $STANDARD_ALIASES; do
            # Check if the alias exists in the project store
            if ! echo "$PROJECT_ALIASES" | grep -q "^$std_alias$"; then
                # Check if the certificate content exists with a different alias
                CERT_FOUND=0
                for proj_alias in $PROJECT_ALIASES; do
                    if [ -f "$PROJECT_CERTS_DIR/$proj_alias.cer" ] && [ -f "$STANDARD_CERTS_DIR/$std_alias.cer" ]; then
                        if diff -q "$PROJECT_CERTS_DIR/$proj_alias.cer" "$STANDARD_CERTS_DIR/$std_alias.cer" &> /dev/null; then
                            CERT_FOUND=1
                            break
                        fi
                    fi
                done
                
                if [ "$CERT_FOUND" -eq 0 ]; then
                    ((MISSING_COUNT++))
                    MISSING_ALIASES="$MISSING_ALIASES $std_alias"
                fi
            fi
        done
        
        echo "  Missing $MISSING_COUNT certificates from standard trust store" >> "$LOG_FILE"
        
        # Create a backup of the original file if we're going to modify it
        if [ "$MODE" -ne 1 ]; then
            cp "$file" "$file.bak"
            echo "  Created backup: $file.bak"
        fi
        
        case "$MODE" in
            1) # Compare and log only
                echo "  Comparison complete. No changes made to the file."
                
                # Add fix commands to the commands file
                if [ "$MISSING_COUNT" -gt 0 ]; then
                    echo "" >> "$COMMANDS_FILE"
                    echo "# Fix for: $file (missing $MISSING_COUNT certificates)" >> "$COMMANDS_FILE"
                    echo "echo \"Fixing $file...\"" >> "$COMMANDS_FILE"
                    echo "cp \"$file\" \"$file.bak\"  # Create backup" >> "$COMMANDS_FILE"
                    
                    # Option 1: Import missing certificates
                    echo "" >> "$COMMANDS_FILE"
                    echo "# Option 1: Import missing certificates" >> "$COMMANDS_FILE"
                    for alias in $MISSING_ALIASES; do
                        echo "# Import certificate: $alias" >> "$COMMANDS_FILE"
                        if [ -n "$TRUST_STORE_URL" ]; then
                            # If we used a URL, we need to extract the certificate first
                            echo "TEMP_DIR=\$(mktemp -d)" >> "$COMMANDS_FILE"
                            echo "trap 'rm -rf \"\$TEMP_DIR\"' EXIT" >> "$COMMANDS_FILE"
                            echo "DOWNLOADED_STORE=\"\$TEMP_DIR/downloaded.jks\"" >> "$COMMANDS_FILE"
                            echo "" >> "$COMMANDS_FILE"
                            echo "# Download the standard trust store" >> "$COMMANDS_FILE"
                            echo "if command -v curl &> /dev/null; then" >> "$COMMANDS_FILE"
                            echo "    curl -s -o \"\$DOWNLOADED_STORE\" \"$TRUST_STORE_URL\"" >> "$COMMANDS_FILE"
                            echo "elif command -v wget &> /dev/null; then" >> "$COMMANDS_FILE"
                            echo "    wget -q -O \"\$DOWNLOADED_STORE\" \"$TRUST_STORE_URL\"" >> "$COMMANDS_FILE"
                            echo "else" >> "$COMMANDS_FILE"
                            echo "    echo \"Error: Neither curl nor wget is available.\"" >> "$COMMANDS_FILE"
                            echo "    exit 1" >> "$COMMANDS_FILE"
                            echo "fi" >> "$COMMANDS_FILE"
                            echo "" >> "$COMMANDS_FILE"
                            echo "# Export the certificate" >> "$COMMANDS_FILE"
                            echo "keytool -exportcert -keystore \"\$DOWNLOADED_STORE\" -storepass \"\$JKS_PASSWORD\" -alias \"$alias\" -file \"\$TEMP_DIR/$alias.cer\" -rfc" >> "$COMMANDS_FILE"
                            echo "" >> "$COMMANDS_FILE"
                            echo "# Import the certificate" >> "$COMMANDS_FILE"
                            echo "keytool -importcert -noprompt -keystore \"$file\" -storepass \"\$JKS_PASSWORD\" -alias \"$alias\" -file \"\$TEMP_DIR/$alias.cer\"" >> "$COMMANDS_FILE"
                        else
                            # If we used a local file, we can import directly
                            echo "keytool -exportcert -keystore \"$STANDARD_TRUST_STORE\" -storepass \"\$JKS_PASSWORD\" -alias \"$alias\" -file \"/tmp/$alias.cer\" -rfc" >> "$COMMANDS_FILE"
                            echo "keytool -importcert -noprompt -keystore \"$file\" -storepass \"\$JKS_PASSWORD\" -alias \"$alias\" -file \"/tmp/$alias.cer\"" >> "$COMMANDS_FILE"
                            echo "rm -f \"/tmp/$alias.cer\"" >> "$COMMANDS_FILE"
                        fi
                        echo "" >> "$COMMANDS_FILE"
                    done
                    
                    # Option 2: Replace with standard trust store
                    echo "# Option 2: Replace with standard trust store" >> "$COMMANDS_FILE"
                    if [ -n "$TRUST_STORE_URL" ]; then
                        # If we used a URL, provide the command to download and use it
                        echo "# Download and use the standard trust store:" >> "$COMMANDS_FILE"
                        echo "# if command -v curl &> /dev/null; then" >> "$COMMANDS_FILE"
                        echo "#     curl -s -o \"$file\" \"$TRUST_STORE_URL\"" >> "$COMMANDS_FILE"
                        echo "# elif command -v wget &> /dev/null; then" >> "$COMMANDS_FILE"
                        echo "#     wget -q -O \"$file\" \"$TRUST_STORE_URL\"" >> "$COMMANDS_FILE"
                        echo "# else" >> "$COMMANDS_FILE"
                        echo "#     echo \"Error: Neither curl nor wget is available.\"" >> "$COMMANDS_FILE"
                        echo "#     exit 1" >> "$COMMANDS_FILE"
                        echo "# fi" >> "$COMMANDS_FILE"
                    else
                        # If we used a local file, provide the command to copy it
                        echo "# cp \"$STANDARD_TRUST_STORE\" \"$file\"" >> "$COMMANDS_FILE"
                    fi
                    
                    echo "echo \"Updated: $file (backup saved as $file.bak)\"" >> "$COMMANDS_FILE"
                    echo "" >> "$COMMANDS_FILE"
                    
                    echo "  Fix commands added to $COMMANDS_FILE"
                    echo "  To fix, run: $COMMANDS_FILE or run this script with -m 2"
                fi
                ;;
                
            2) # Compare and append
                if [ "$MISSING_COUNT" -gt 0 ]; then
                    echo "  Updating trust store by importing $MISSING_COUNT certificates from standard store..."
                    
                    for alias in $MISSING_ALIASES; do
                        echo "    Importing certificate: $alias"
                        # Export the certificate from the standard store
                        keytool -exportcert -keystore "$STANDARD_TRUST_STORE" -storepass "$JKS_PASSWORD" -alias "$alias" -file "$TEMP_DIR/$alias.cer" -rfc
                        
                        # Import the certificate into the project store
                        keytool -importcert -noprompt -keystore "$file" -storepass "$JKS_PASSWORD" -alias "$alias" -file "$TEMP_DIR/$alias.cer"
                        
                        # Clean up
                        rm -f "$TEMP_DIR/$alias.cer"
                    done
                    
                    echo "  Updated: $file (imported $MISSING_COUNT certificates)" >> "$LOG_FILE"
                    echo "  Updated: $file (backup saved as $file.bak)"
                else
                    echo "  No missing certificates found. File unchanged."
                    echo "  No missing certificates found. File unchanged." >> "$LOG_FILE"
                fi
                ;;
                
            3) # Compare and replace
                echo "  Replacing trust store with standard trust store..."
                cp "$STANDARD_TRUST_STORE" "$file"
                echo "  Replaced: $file with standard trust store" >> "$LOG_FILE"
                echo "  Replaced: $file (backup saved as $file.bak)"
                ;;
        esac
        
        echo "----------------------------------------" >> "$LOG_FILE"
    else
        echo "  Warning: File appears to be a JKS file but could not be opened with password: $JKS_PASSWORD"
        echo "  Warning: File appears to be a JKS file but could not be opened with password: $JKS_PASSWORD" >> "$LOG_FILE"
    fi
done

# Make the commands file executable
if [ "$MODE" -eq 1 ]; then
    chmod +x "$COMMANDS_FILE"
    echo "Fix commands have been saved to $COMMANDS_FILE"
    echo "Run this file to apply the fixes: ./$COMMANDS_FILE"
fi

echo "JKS trust store comparison and update completed."
echo "See $LOG_FILE for details." 