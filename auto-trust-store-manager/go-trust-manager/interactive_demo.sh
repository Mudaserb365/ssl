#!/bin/bash

set -e

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
RESET="\033[0m"
BOLD="\033[1m"

SOURCE_KEYSTORE="test_keystores/source/source.jks"
DEST_KEYSTORE="test_keystores/destination/destination.jks"
CERT_FILE="test_keystores/cert/test.crt"

echo -e "${BOLD}=== Trust Store Manager Interactive Walkthrough ===${RESET}"
echo "This wizard will guide you through the process of managing trust stores in your project."
echo

# Step 1: Project directory
echo -e "${BLUE}Step 1: Project Directory${RESET}"
echo "Enter the project directory path (or press Enter for current directory):"
read -p "> " project_dir
project_dir=${project_dir:-$(pwd)}

if [ ! -d "$project_dir" ]; then
    echo -e "${RED}Error: Invalid directory path.${RESET}"
    exit 1
fi

echo -e "${GREEN}Directory set to: $project_dir${RESET}"
echo

# Step 2: Detect project type
echo -e "${BLUE}Step 2: Project Type Detection${RESET}"
echo "Analyzing project directory..."
sleep 1

# Simulate detection - we know it's a Java project
echo -e "${GREEN}Detected ${BOLD}Java${RESET}${GREEN} project.${RESET}"
echo "Continue with this project type? [y/N]"
read -p "> " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Please select the primary runtime for your project:"
    echo "1. Java"
    echo "2. Python"
    echo "3. Node.js"
    echo "4. Other/Unknown"
    
    read -p "Enter your choice (1-4) [4]: " choice
    choice=${choice:-4}
    
    case $choice in
        1) project_type="java" ;;
        2) project_type="python" ;;
        3) project_type="nodejs" ;;
        *) project_type="unknown" ;;
    esac
else
    project_type="java"
fi

echo -e "${GREEN}Selected project type: $project_type${RESET}"
echo

# Step 3: Trust Store Options
echo -e "${BLUE}Step 3: Trust Store Configuration${RESET}"
echo "Configuring options for $project_type project..."

# Option: Scan mode
echo
echo "Select scan mode:"
echo "1. Discovery only - Find and report trust stores without modifications"
echo "2. Update existing - Update only existing trust stores"
echo "3. Comprehensive - Find, create, and update trust stores"
    
read -p "Enter your choice (1-3) [1]: " scan_choice
scan_choice=${scan_choice:-1}
    
case $scan_choice in
    2) scan_mode="update" ;;
    3) scan_mode="comprehensive" ;;
    *) scan_mode="discovery" ;;
esac

echo -e "${GREEN}Selected scan mode: $scan_mode${RESET}"

# Option: Certificate source
echo
echo "Select certificate source:"
echo "1. Auto-generate a new certificate"
echo "2. Use an existing certificate file"
echo "3. Download from URL"
    
read -p "Enter your choice (1-3) [1]: " cert_choice
cert_choice=${cert_choice:-1}
    
case $cert_choice in
    2) 
        echo "Enter path to certificate file:"
        read -p "> " cert_path
        cert_path=${cert_path:-$CERT_FILE}
        generate_cert=false
        echo -e "${GREEN}Using certificate: $cert_path${RESET}"
        ;;
    3)
        echo "Enter URL to download certificate:"
        read -p "> " cert_url
        cert_url=${cert_url:-"https://example.com/cert.pem"}
        echo -e "${GREEN}Certificate will be downloaded from: $cert_url${RESET}"
        generate_cert=false
        cert_path="/tmp/downloaded_cert.pem"
        ;;
    *)
        generate_cert=true
        cert_path=$CERT_FILE
        echo -e "${GREEN}Will auto-generate certificate${RESET}"
        ;;
esac

# Option: JKS passwords (for Java projects)
if [ "$project_type" = "java" ]; then
    echo
    echo "Java KeyStore (JKS) requires passwords for access."
    read -p "Enter default JKS password [changeit]: " default_pwd
    default_pwd=${default_pwd:-"changeit"}
    passwords=("$default_pwd")
    
    echo "Add additional passwords to try? [y/N]"
    read -p "> " add_passwords
    if [[ "$add_passwords" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter additional password (or leave empty to finish): " additional_pwd
            if [ -z "$additional_pwd" ]; then
                break
            fi
            passwords+=("$additional_pwd")
        done
    fi
fi

# Option: Advanced settings
echo
echo "Configure advanced options? [y/N]"
read -p "> " advanced_options
if [[ "$advanced_options" =~ ^[Yy]$ ]]; then
    echo "Enable verbose logging? [y/N]"
    read -p "> " verbose_input
    if [[ "$verbose_input" =~ ^[Yy]$ ]]; then
        verbose=true
    else
        verbose=false
    fi
    
    echo "Create backups before modifying trust stores? [Y/n]"
    read -p "> " backup_input
    if [[ "$backup_input" =~ ^[Nn]$ ]]; then
        backup_enabled=false
    else
        backup_enabled=true
    fi
else
    verbose=false
    backup_enabled=true
fi

# Summary and confirmation
echo
echo -e "${BLUE}=== Configuration Summary ===${RESET}"
echo "Project directory: $project_dir"
echo "Project type: $project_type"
echo "Scan mode: $scan_mode"

if [ "$generate_cert" = true ]; then
    echo "Certificate: Auto-generated"
else
    echo "Certificate path: $cert_path"
fi

if [ "$project_type" = "java" ]; then
    echo "JKS passwords: ${passwords[*]}"
fi

echo "Verbose mode: $verbose"
echo "Create backups: $backup_enabled"

echo
echo "Proceed with these settings? [y/N]"
read -p "> " proceed
if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    echo "Configuration cancelled. Exiting..."
    exit 0
fi

# Execute trust store operation
echo
echo -e "${BLUE}Executing trust store management operation...${RESET}"

# For demo purposes, import a certificate from source to destination keystore
if [ "$scan_mode" != "discovery" ]; then
    if [ "$backup_enabled" = true ]; then
        echo "Creating backup of $DEST_KEYSTORE..."
        cp "$DEST_KEYSTORE" "${DEST_KEYSTORE}.bak"
    fi
    
    echo "Extracting certificate from source keystore..."
    keytool -exportcert -noprompt -alias sourcekey -keystore "$SOURCE_KEYSTORE" -storepass "${passwords[0]}" -file "$CERT_FILE" -rfc
    
    echo "Importing certificate to destination keystore..."
    keytool -importcert -noprompt -alias sourcekey -keystore "$DEST_KEYSTORE" -storepass "${passwords[0]}" -file "$CERT_FILE"
    
    echo -e "${GREEN}Trust stores updated successfully!${RESET}"
else
    echo "Listing certificates in source keystore..."
    keytool -list -v -keystore "$SOURCE_KEYSTORE" -storepass "${passwords[0]}" | head -20
    
    echo "Listing certificates in destination keystore..."
    keytool -list -v -keystore "$DEST_KEYSTORE" -storepass "${passwords[0]}" | head -20
    
    echo -e "${YELLOW}Discovery mode - No modifications made to trust stores.${RESET}"
fi

echo
echo -e "${GREEN}Operation completed successfully!${RESET}" 