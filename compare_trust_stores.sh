#!/bin/bash

# Script to search for trust stores in a Python project, compare with a standard trust store,
# and update them by appending trust chains from the standard store

set -e

# Display usage information
usage() {
    echo "Usage: $0 -s <standard_trust_store> [-d <project_directory>] [-e <extensions>] [-m <mode>] [-u <url>] [-h]"
    echo "  -s  Path to the standard trust store (PEM file)"
    echo "  -d  Directory to search for trust stores (default: current directory)"
    echo "  -e  Comma-separated list of file extensions to search for (default: pem,crt,cert)"
    echo "  -m  Mode of operation (default: 1)"
    echo "      1: Compare and log differences only"
    echo "      2: Compare and append missing certificates"
    echo "      3: Compare and replace with standard trust store"
    echo "  -u  URL to download standard trust store (instead of using -s)"
    echo "  -h  Display this help message"
    exit 1
}

# Default values
PROJECT_DIR="."
EXTENSIONS="pem,crt,cert"
STANDARD_TRUST_STORE=""
TRUST_STORE_URL=""
MODE=1  # Default mode: compare and log

# Parse command line arguments
while getopts "s:d:e:m:u:h" opt; do
    case $opt in
        s) STANDARD_TRUST_STORE="$OPTARG" ;;
        d) PROJECT_DIR="$OPTARG" ;;
        e) EXTENSIONS="$OPTARG" ;;
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

# Convert extensions to find pattern
FIND_PATTERN=$(echo "$EXTENSIONS" | sed 's/,/\\|/g')

echo "Searching for trust stores in '$PROJECT_DIR' with extensions: $EXTENSIONS"
echo "Using standard trust store: $STANDARD_TRUST_STORE"
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Trust store source: Downloaded from $TRUST_STORE_URL"
fi
echo "Mode: $MODE - $([ "$MODE" -eq 1 ] && echo "Compare and log" || [ "$MODE" -eq 2 ] && echo "Compare and append" || echo "Compare and replace")"

# Create a log file
LOG_FILE="trust_store_comparison_$(date +%Y%m%d_%H%M%S).log"
COMMANDS_FILE="fix_commands_$(date +%Y%m%d_%H%M%S).sh"
echo "Logging results to: $LOG_FILE"
echo "Fix commands will be saved to: $COMMANDS_FILE"
echo "Trust Store Comparison Report - $(date)" > "$LOG_FILE"
echo "Standard trust store: $STANDARD_TRUST_STORE" >> "$LOG_FILE"
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Trust store source: Downloaded from $TRUST_STORE_URL" >> "$LOG_FILE"
fi
echo "Mode: $([ "$MODE" -eq 1 ] && echo "Compare and log" || [ "$MODE" -eq 2 ] && echo "Compare and append" || echo "Compare and replace")" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"

# Create commands file header
echo "#!/bin/bash" > "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "# Commands to fix trust stores - generated on $(date)" >> "$COMMANDS_FILE"
echo "# Run this script to apply the fixes identified by compare_trust_stores.sh" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "set -e" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"

# Extract certificates from standard trust store
echo "Extracting certificates from standard trust store..."
STANDARD_CERTS="$TEMP_DIR/standard_certs"
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$STANDARD_TRUST_STORE" > "$STANDARD_CERTS"
STANDARD_CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$STANDARD_CERTS" || echo 0)
echo "Standard trust store contains $STANDARD_CERT_COUNT certificates" >> "$LOG_FILE"

# Find potential trust store files
find "$PROJECT_DIR" -type f -name "*.pem" -o -name "*.crt" -o -name "*.cert" | while read -r file; do
    echo "Processing: $file"
    echo "Processing: $file" >> "$LOG_FILE"
    
    # Check if file contains certificates
    if grep -q "BEGIN CERTIFICATE" "$file"; then
        echo "  Found certificate store in: $file"
        
        # Extract certificates from the found file
        PROJECT_CERTS="$TEMP_DIR/project_certs"
        awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$file" > "$PROJECT_CERTS"
        PROJECT_CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$PROJECT_CERTS" || echo 0)
        echo "  Project trust store contains $PROJECT_CERT_COUNT certificates" >> "$LOG_FILE"
        
        # Find missing certificates
        MISSING_CERTS="$TEMP_DIR/missing_certs"
        > "$MISSING_CERTS"
        MISSING_COUNT=0
        
        while read -r cert; do
            if ! grep -Fxq "$cert" "$PROJECT_CERTS"; then
                echo "$cert" >> "$MISSING_CERTS"
                ((MISSING_COUNT++))
            fi
        done < <(awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$STANDARD_CERTS")
        
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
                    
                    # Option 1: Append using cat
                    echo "" >> "$COMMANDS_FILE"
                    echo "# Option 1: Append missing certificates using cat" >> "$COMMANDS_FILE"
                    echo "cat << 'EOF' >> \"$file\"" >> "$COMMANDS_FILE"
                    cat "$MISSING_CERTS" >> "$COMMANDS_FILE"
                    echo "EOF" >> "$COMMANDS_FILE"
                    
                    # Option 2: Replace with standard trust store
                    echo "" >> "$COMMANDS_FILE"
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
                    echo "  Updating trust store by appending $MISSING_COUNT certificates from standard store..."
                    cat "$file" > "$TEMP_DIR/merged"
                    cat "$MISSING_CERTS" >> "$TEMP_DIR/merged"
                    mv "$TEMP_DIR/merged" "$file"
                    echo "  Updated: $file (appended $MISSING_COUNT certificates)" >> "$LOG_FILE"
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
    fi
done

# Make the commands file executable
if [ "$MODE" -eq 1 ]; then
    chmod +x "$COMMANDS_FILE"
    echo "Fix commands have been saved to $COMMANDS_FILE"
    echo "Run this file to apply the fixes: ./$COMMANDS_FILE"
fi

echo "Trust store comparison and update completed."
echo "See $LOG_FILE for details." 