#!/bin/bash

# Trust Store Manager Interactive Demo
# This script provides a guided experience to use the Trust Store Manager

# Colors for better UI
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Detect OS and architecture for using the correct binary
detect_binary() {
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  
  if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="amd64"
  elif [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
    ARCH="arm64"
  else
    ARCH="amd64" # Default to amd64 if unknown
  fi
  
  if [[ "$OS" == "darwin" ]]; then
    BINARY="../bin/trust-store-manager-darwin-$ARCH"
  elif [[ "$OS" == "linux" ]]; then
    BINARY="../bin/trust-store-manager-linux-$ARCH"
  elif [[ "$OS" =~ windows ]]; then
    BINARY="../bin/trust-store-manager-windows-amd64.exe"
  else
    echo -e "${RED}Unsupported operating system: $OS${NC}"
    exit 1
  fi
  
  if [[ ! -f "$BINARY" ]]; then
    echo -e "${RED}Binary not found: $BINARY${NC}"
    echo -e "${YELLOW}Please make sure you're running this script from the scripts directory.${NC}"
    exit 1
  fi
  
  echo "$BINARY"
}

# Welcome message
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}   Trust Store Manager Interactive Demo${NC}"
echo -e "${GREEN}=======================================${NC}"
echo 
echo -e "${BLUE}This guided demo will help you manage trust stores in your project.${NC}"
echo

# Step 1: Choose project directory
echo -e "${YELLOW}Step 1: Select your project directory${NC}"
echo -e "Enter the path to your project (or press Enter for current directory):"
read PROJECT_DIR

if [[ -z "$PROJECT_DIR" ]]; then
  PROJECT_DIR="$(pwd)"
  echo -e "Using current directory: ${BLUE}$PROJECT_DIR${NC}"
else
  if [[ ! -d "$PROJECT_DIR" ]]; then
    echo -e "${RED}Error: Directory does not exist${NC}"
    exit 1
  fi
  echo -e "Using directory: ${BLUE}$PROJECT_DIR${NC}"
fi

echo

# Step 2: Choose operation mode
echo -e "${YELLOW}Step 2: Choose operation mode${NC}"
echo -e "1) Scan only - Find trust stores without modifying them"
echo -e "2) Update trust stores - Add a certificate to trust stores"
echo -e "3) Compare trust stores - Check if trust stores match a baseline"
echo -e "Enter your choice (1-3):"
read OPERATION_CHOICE

OPERATION_ARGS=""
case $OPERATION_CHOICE in
  1)
    echo -e "Selected: ${BLUE}Scan only${NC}"
    OPERATION_ARGS="--scan-only"
    ;;
  2)
    echo -e "Selected: ${BLUE}Update trust stores${NC}"
    echo -e "Enter the path to the certificate file to add (.pem, .crt):"
    read CERT_PATH
    if [[ ! -f "$CERT_PATH" ]]; then
      echo -e "${RED}Error: Certificate file does not exist${NC}"
      exit 1
    fi
    OPERATION_ARGS="-c \"$CERT_PATH\""
    ;;
  3)
    echo -e "Selected: ${BLUE}Compare trust stores${NC}"
    echo -e "Enter the path to the baseline trust chain (.pem, .crt):"
    read BASELINE_PATH
    if [[ ! -f "$BASELINE_PATH" ]]; then
      echo -e "${RED}Error: Baseline file does not exist${NC}"
      exit 1
    fi
    OPERATION_ARGS="-b \"$BASELINE_PATH\" --compare-only"
    ;;
  *)
    echo -e "${RED}Invalid choice. Defaulting to scan only.${NC}"
    OPERATION_ARGS="--scan-only"
    ;;
esac

echo

# Step 3: Handle Java keystore passwords if needed
if [[ $(find "$PROJECT_DIR" -name "*.jks" -o -name "*.keystore" -o -name "*.truststore" 2>/dev/null) ]]; then
  echo -e "${YELLOW}Step 3: Java KeyStore configuration${NC}"
  echo -e "Java KeyStores detected. Enter passwords (space-separated, default is 'changeit'):"
  read JKS_PASSWORDS
  
  if [[ -z "$JKS_PASSWORDS" ]]; then
    JKS_PASSWORDS="changeit"
  fi
  
  echo -e "Using passwords: ${BLUE}$JKS_PASSWORDS${NC}"
  OPERATION_ARGS="$OPERATION_ARGS -p \"$JKS_PASSWORDS\""
fi

echo

# Step 4: Verbose mode option
echo -e "${YELLOW}Step 4: Verbose output${NC}"
echo -e "Would you like verbose output? (y/n, default: n):"
read VERBOSE_CHOICE

if [[ "$VERBOSE_CHOICE" == "y" || "$VERBOSE_CHOICE" == "Y" ]]; then
  echo -e "Verbose mode: ${BLUE}Enabled${NC}"
  OPERATION_ARGS="$OPERATION_ARGS -v"
else
  echo -e "Verbose mode: ${BLUE}Disabled${NC}"
fi

echo

# Step 5: Execute the command
BINARY=$(detect_binary)
COMMAND="$BINARY -d \"$PROJECT_DIR\" $OPERATION_ARGS"

echo -e "${YELLOW}Ready to execute:${NC}"
echo -e "${BLUE}$COMMAND${NC}"
echo
echo -e "Press Enter to continue or Ctrl+C to cancel..."
read

echo -e "${GREEN}Executing Trust Store Manager...${NC}"
echo -e "${GREEN}=======================================${NC}"

eval "$COMMAND"

EXIT_CODE=$?
echo

if [[ $EXIT_CODE -eq 0 ]]; then
  echo -e "${GREEN}=======================================${NC}"
  echo -e "${GREEN}Operation completed successfully!${NC}"
  echo -e "${GREEN}=======================================${NC}"
else
  echo -e "${RED}=======================================${NC}"
  echo -e "${RED}Operation failed with exit code: $EXIT_CODE${NC}"
  echo -e "${RED}=======================================${NC}"
fi

echo
echo -e "${BLUE}Thank you for using the Trust Store Manager Interactive Demo.${NC}"
echo -e "${BLUE}For more options, see the README.md file.${NC}" 