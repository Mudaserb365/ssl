#!/bin/bash

# Script to find and update trust stores in Docker containers
# Compares with a standard trust store and updates them by appending trust chains

set -e

# Display usage information
usage() {
    echo "Usage: $0 -s <standard_trust_store> -c <container_id> [-p <path_in_container>] [-m <mode>] [-u <url>] [-h]"
    echo "  -s  Path to the standard trust store (PEM file)"
    echo "  -c  Docker container ID or name"
    echo "  -p  Path in container to search for trust stores (default: /)"
    echo "  -m  Mode of operation (default: 2)"
    echo "      1: Compare and log differences only"
    echo "      2: Compare and append missing certificates"
    echo "      3: Compare and replace with standard trust store"
    echo "  -u  URL to download standard trust store (instead of using -s)"
    echo "  -h  Display this help message"
    exit 1
}

# Default values
CONTAINER_ID=""
CONTAINER_PATH="/"
STANDARD_TRUST_STORE=""
TRUST_STORE_URL=""
MODE=2  # Default mode: compare and append

# Parse command line arguments
while getopts "s:c:p:m:u:h" opt; do
    case $opt in
        s) STANDARD_TRUST_STORE="$OPTARG" ;;
        c) CONTAINER_ID="$OPTARG" ;;
        p) CONTAINER_PATH="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        u) TRUST_STORE_URL="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: docker is not available. Please install Docker."
    exit 1
fi

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

# Check if container ID is provided
if [ -z "$CONTAINER_ID" ]; then
    echo "Error: Docker container ID or name (-c) is required"
    usage
fi

# Check if container exists and is running
if ! docker ps -q -f "id=$CONTAINER_ID" -f "status=running" &> /dev/null && ! docker ps -q -f "name=$CONTAINER_ID" -f "status=running" &> /dev/null; then
    echo "Error: Container '$CONTAINER_ID' does not exist or is not running"
    exit 1
fi

# Validate mode
if [[ ! "$MODE" =~ ^[1-3]$ ]]; then
    echo "Error: Invalid mode '$MODE'. Mode must be 1, 2, or 3."
    usage
fi

echo "Searching for trust stores in container '$CONTAINER_ID' at path '$CONTAINER_PATH'"
echo "Using standard trust store: $STANDARD_TRUST_STORE"
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Trust store source: Downloaded from $TRUST_STORE_URL"
fi
echo "Mode: $MODE - $([ "$MODE" -eq 1 ] && echo "Compare and log" || [ "$MODE" -eq 2 ] && echo "Compare and append" || echo "Compare and replace")"

# Create a log file
LOG_FILE="docker_trust_store_comparison_$(date +%Y%m%d_%H%M%S).log"
COMMANDS_FILE="fix_docker_commands_$(date +%Y%m%d_%H%M%S).sh"
echo "Logging results to: $LOG_FILE"
echo "Fix commands will be saved to: $COMMANDS_FILE"
echo "Docker Trust Store Comparison Report - $(date)" > "$LOG_FILE"
echo "Container: $CONTAINER_ID" >> "$LOG_FILE"
echo "Standard trust store: $STANDARD_TRUST_STORE" >> "$LOG_FILE"
if [ -n "$TRUST_STORE_URL" ]; then
    echo "Trust store source: Downloaded from $TRUST_STORE_URL" >> "$LOG_FILE"
fi
echo "Mode: $([ "$MODE" -eq 1 ] && echo "Compare and log" || [ "$MODE" -eq 2 ] && echo "Compare and append" || echo "Compare and replace")" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"

# Create commands file header
echo "#!/bin/bash" > "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "# Commands to fix Docker container trust stores - generated on $(date)" >> "$COMMANDS_FILE"
echo "# Run this script to apply the fixes identified by docker_trust_store_update.sh" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "set -e" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "CONTAINER_ID=\"$CONTAINER_ID\"" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"
echo "# Check if container is running" >> "$COMMANDS_FILE"
echo "if ! docker ps -q -f \"id=\$CONTAINER_ID\" -f \"status=running\" &> /dev/null && ! docker ps -q -f \"name=\$CONTAINER_ID\" -f \"status=running\" &> /dev/null; then" >> "$COMMANDS_FILE"
echo "    echo \"Error: Container '\$CONTAINER_ID' does not exist or is not running\"" >> "$COMMANDS_FILE"
echo "    exit 1" >> "$COMMANDS_FILE"
echo "fi" >> "$COMMANDS_FILE"
echo "" >> "$COMMANDS_FILE"

# Extract certificates from standard trust store
echo "Extracting certificates from standard trust store..."
STANDARD_CERTS="$TEMP_DIR/standard_certs"
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$STANDARD_TRUST_STORE" > "$STANDARD_CERTS"
STANDARD_CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$STANDARD_CERTS" || echo 0)
echo "Standard trust store contains $STANDARD_CERT_COUNT certificates" >> "$LOG_FILE"

# Copy standard trust store to a temporary file for docker cp
STANDARD_TRUST_STORE_COPY="$TEMP_DIR/standard_trust_store.pem"
cp "$STANDARD_TRUST_STORE" "$STANDARD_TRUST_STORE_COPY"

# Find all PEM files in the container
echo "Finding PEM files in container..."
PEM_FILES=$(docker exec "$CONTAINER_ID" find "$CONTAINER_PATH" -type f -name "*.pem" -o -name "*.crt" -o -name "*.cert" 2>/dev/null || echo "")

if [ -z "$PEM_FILES" ]; then
    echo "No PEM files found in container at path '$CONTAINER_PATH'"
    echo "No PEM files found in container at path '$CONTAINER_PATH'" >> "$LOG_FILE"
    exit 0
fi

echo "Found $(echo "$PEM_FILES" | wc -l) potential trust store files"

# Process each PEM file
echo "$PEM_FILES" | while read -r container_file; do
    echo "Processing: $container_file"
    echo "Processing: $container_file" >> "$LOG_FILE"
    
    # Copy the file from container to local temp directory
    LOCAL_FILE="$TEMP_DIR/$(basename "$container_file")"
    if ! docker cp "$CONTAINER_ID:$container_file" "$LOCAL_FILE"; then
        echo "  Error: Could not copy file from container"
        echo "  Error: Could not copy file from container" >> "$LOG_FILE"
        continue
    fi
    
    # Check if file contains certificates
    if grep -q "BEGIN CERTIFICATE" "$LOCAL_FILE"; then
        echo "  Found certificate store in: $container_file"
        
        # Extract certificates from the found file
        PROJECT_CERTS="$TEMP_DIR/project_certs"
        awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$LOCAL_FILE" > "$PROJECT_CERTS"
        PROJECT_CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$PROJECT_CERTS" || echo 0)
        echo "  Container trust store contains $PROJECT_CERT_COUNT certificates" >> "$LOG_FILE"
        
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
        
        case "$MODE" in
            1) # Compare and log only
                echo "  Comparison complete. No changes made to the file."
                
                # Add fix commands to the commands file
                if [ "$MISSING_COUNT" -gt 0 ]; then
                    echo "" >> "$COMMANDS_FILE"
                    echo "# Fix for: $container_file (missing $MISSING_COUNT certificates)" >> "$COMMANDS_FILE"
                    echo "echo \"Fixing $container_file...\"" >> "$COMMANDS_FILE"
                    
                    # Create a temporary directory for the operation
                    echo "TEMP_DIR=\$(mktemp -d)" >> "$COMMANDS_FILE"
                    echo "trap 'rm -rf \"\$TEMP_DIR\"' EXIT" >> "$COMMANDS_FILE"
                    echo "" >> "$COMMANDS_FILE"
                    
                    # Copy the file from container
                    echo "# Copy the file from container" >> "$COMMANDS_FILE"
                    echo "docker cp \"\$CONTAINER_ID:$container_file\" \"\$TEMP_DIR/original.pem\"" >> "$COMMANDS_FILE"
                    echo "cp \"\$TEMP_DIR/original.pem\" \"\$TEMP_DIR/original.pem.bak\"  # Create backup" >> "$COMMANDS_FILE"
                    echo "" >> "$COMMANDS_FILE"
                    
                    # Option 1: Append missing certificates
                    echo "# Option 1: Append missing certificates" >> "$COMMANDS_FILE"
                    echo "cat << 'EOF' >> \"\$TEMP_DIR/original.pem\"" >> "$COMMANDS_FILE"
                    cat "$MISSING_CERTS" >> "$COMMANDS_FILE"
                    echo "EOF" >> "$COMMANDS_FILE"
                    echo "" >> "$COMMANDS_FILE"
                    
                    # Copy the updated file back to the container
                    echo "# Copy the updated file back to the container" >> "$COMMANDS_FILE"
                    echo "docker cp \"\$TEMP_DIR/original.pem\" \"\$CONTAINER_ID:$container_file\"" >> "$COMMANDS_FILE"
                    echo "" >> "$COMMANDS_FILE"
                    
                    # Option 2: Replace with standard trust store
                    echo "# Option 2: Replace with standard trust store (commented out)" >> "$COMMANDS_FILE"
                    if [ -n "$TRUST_STORE_URL" ]; then
                        # If we used a URL, provide the command to download and use it
                        echo "# Download and use the standard trust store:" >> "$COMMANDS_FILE"
                        echo "# if command -v curl &> /dev/null; then" >> "$COMMANDS_FILE"
                        echo "#     curl -s -o \"\$TEMP_DIR/standard.pem\" \"$TRUST_STORE_URL\"" >> "$COMMANDS_FILE"
                        echo "#     docker cp \"\$TEMP_DIR/standard.pem\" \"\$CONTAINER_ID:$container_file\"" >> "$COMMANDS_FILE"
                        echo "# elif command -v wget &> /dev/null; then" >> "$COMMANDS_FILE"
                        echo "#     wget -q -O \"\$TEMP_DIR/standard.pem\" \"$TRUST_STORE_URL\"" >> "$COMMANDS_FILE"
                        echo "#     docker cp \"\$TEMP_DIR/standard.pem\" \"\$CONTAINER_ID:$container_file\"" >> "$COMMANDS_FILE"
                        echo "# else" >> "$COMMANDS_FILE"
                        echo "#     echo \"Error: Neither curl nor wget is available.\"" >> "$COMMANDS_FILE"
                        echo "#     exit 1" >> "$COMMANDS_FILE"
                        echo "# fi" >> "$COMMANDS_FILE"
                    else
                        # If we used a local file, provide the command to copy it
                        echo "# docker cp \"$STANDARD_TRUST_STORE\" \"\$CONTAINER_ID:$container_file\"" >> "$COMMANDS_FILE"
                    fi
                    
                    echo "echo \"Updated: $container_file\"" >> "$COMMANDS_FILE"
                    echo "" >> "$COMMANDS_FILE"
                    
                    echo "  Fix commands added to $COMMANDS_FILE"
                    echo "  To fix, run: $COMMANDS_FILE or run this script with -m 2"
                fi
                ;;
                
            2) # Compare and append
                if [ "$MISSING_COUNT" -gt 0 ]; then
                    echo "  Updating trust store by appending $MISSING_COUNT certificates from standard store..."
                    
                    # Create a merged file
                    MERGED_FILE="$TEMP_DIR/merged.pem"
                    cat "$LOCAL_FILE" > "$MERGED_FILE"
                    cat "$MISSING_CERTS" >> "$MERGED_FILE"
                    
                    # Copy the merged file back to the container
                    if docker cp "$MERGED_FILE" "$CONTAINER_ID:$container_file"; then
                        echo "  Updated: $container_file (appended $MISSING_COUNT certificates)" >> "$LOG_FILE"
                        echo "  Updated: $container_file (appended $MISSING_COUNT certificates)"
                    else
                        echo "  Error: Failed to update file in container" >> "$LOG_FILE"
                        echo "  Error: Failed to update file in container"
                    fi
                else
                    echo "  No missing certificates found. File unchanged."
                    echo "  No missing certificates found. File unchanged." >> "$LOG_FILE"
                fi
                ;;
                
            3) # Compare and replace
                echo "  Replacing trust store with standard trust store..."
                
                # Copy the standard trust store to the container
                if docker cp "$STANDARD_TRUST_STORE_COPY" "$CONTAINER_ID:$container_file"; then
                    echo "  Replaced: $container_file with standard trust store" >> "$LOG_FILE"
                    echo "  Replaced: $container_file with standard trust store"
                else
                    echo "  Error: Failed to replace file in container" >> "$LOG_FILE"
                    echo "  Error: Failed to replace file in container"
                fi
                ;;
        esac
        
        echo "----------------------------------------" >> "$LOG_FILE"
    else
        echo "  File does not contain certificates, skipping"
        echo "  File does not contain certificates, skipping" >> "$LOG_FILE"
    fi
done

# Make the commands file executable
if [ "$MODE" -eq 1 ]; then
    chmod +x "$COMMANDS_FILE"
    echo "Fix commands have been saved to $COMMANDS_FILE"
    echo "Run this file to apply the fixes: ./$COMMANDS_FILE"
fi

echo "Docker trust store comparison and update completed."
echo "See $LOG_FILE for details." 