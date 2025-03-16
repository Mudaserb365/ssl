#!/bin/bash

# Script to search for trust stores in a Python project, compare with a standard trust store,
# and update them by appending trust chains from the standard store

set -e

# Display usage information
usage() {
    echo "Usage: $0 -s <standard_trust_store> [-d <project_directory>] [-e <extensions>] [-h]"
    echo "  -s  Path to the standard trust store (PEM file)"
    echo "  -d  Directory to search for trust stores (default: current directory)"
    echo "  -e  Comma-separated list of file extensions to search for (default: pem,crt,cert)"
    echo "  -h  Display this help message"
    exit 1
}

# Default values
PROJECT_DIR="."
EXTENSIONS="pem,crt,cert"
STANDARD_TRUST_STORE=""

# Parse command line arguments
while getopts "s:d:e:h" opt; do
    case $opt in
        s) STANDARD_TRUST_STORE="$OPTARG" ;;
        d) PROJECT_DIR="$OPTARG" ;;
        e) EXTENSIONS="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check if standard trust store is provided
if [ -z "$STANDARD_TRUST_STORE" ]; then
    echo "Error: Standard trust store file (-s) is required"
    usage
fi

# Check if standard trust store exists
if [ ! -f "$STANDARD_TRUST_STORE" ]; then
    echo "Error: Standard trust store file '$STANDARD_TRUST_STORE' does not exist"
    exit 1
fi

# Convert extensions to find pattern
FIND_PATTERN=$(echo "$EXTENSIONS" | sed 's/,/\\|/g')

echo "Searching for trust stores in '$PROJECT_DIR' with extensions: $EXTENSIONS"
echo "Using standard trust store: $STANDARD_TRUST_STORE"

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Extract certificates from standard trust store
echo "Extracting certificates from standard trust store..."
STANDARD_CERTS="$TEMP_DIR/standard_certs"
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$STANDARD_TRUST_STORE" > "$STANDARD_CERTS"

# Find potential trust store files
find "$PROJECT_DIR" -type f -name "*.pem" -o -name "*.crt" -o -name "*.cert" | while read -r file; do
    echo "Processing: $file"
    
    # Check if file contains certificates
    if grep -q "BEGIN CERTIFICATE" "$file"; then
        echo "  Found certificate store in: $file"
        
        # Extract certificates from the found file
        PROJECT_CERTS="$TEMP_DIR/project_certs"
        awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$file" > "$PROJECT_CERTS"
        
        # Create a backup of the original file
        cp "$file" "$file.bak"
        
        # Append standard certificates to the file
        echo "  Updating trust store by appending certificates from standard store..."
        cat "$file" > "$TEMP_DIR/merged"
        
        # Find certificates in standard store that are not in the project store
        while read -r cert; do
            if ! grep -Fxq "$cert" "$PROJECT_CERTS"; then
                echo "$cert" >> "$TEMP_DIR/merged"
            fi
        done < <(awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$STANDARD_CERTS")
        
        # Replace the original file with the merged one
        mv "$TEMP_DIR/merged" "$file"
        echo "  Updated: $file (backup saved as $file.bak)"
    fi
done

echo "Trust store comparison and update completed." 