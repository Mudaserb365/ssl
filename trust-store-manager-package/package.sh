#!/bin/bash

# Trust Store Manager Packaging Script
# Creates a distributable archive of the Trust Store Manager

# Colors for better UI
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set variables
VERSION="1.0.0"
PACKAGE_NAME="trust-store-manager-${VERSION}"
ARCHIVE_NAME="${PACKAGE_NAME}.tar.gz"

echo -e "${BLUE}Packaging Trust Store Manager v${VERSION}...${NC}"

# Make sure scripts are executable
chmod +x install.sh
chmod +x scripts/*.sh
chmod +x bin/*

# Create temporary directory with version
echo -e "${BLUE}Creating temporary package structure...${NC}"
mkdir -p ../${PACKAGE_NAME}

# Copy files to the package directory
echo -e "${BLUE}Copying files...${NC}"
cp -r bin ../${PACKAGE_NAME}/
cp -r scripts ../${PACKAGE_NAME}/
cp README.md ../${PACKAGE_NAME}/
cp install.sh ../${PACKAGE_NAME}/

# Create the archive
echo -e "${BLUE}Creating archive...${NC}"
cd ..
tar -czf ${ARCHIVE_NAME} ${PACKAGE_NAME}

# Cleanup
echo -e "${BLUE}Cleaning up...${NC}"
rm -rf ${PACKAGE_NAME}

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}Package created: ${ARCHIVE_NAME}${NC}"
echo -e "${GREEN}=======================================${NC}"
echo
echo -e "${BLUE}You can distribute this archive to users.${NC}"
echo -e "${BLUE}They can extract it and run the install.sh script.${NC}"
echo
echo -e "${YELLOW}Example installation instructions:${NC}"
echo -e "${GREEN}tar -xzf ${ARCHIVE_NAME}${NC}"
echo -e "${GREEN}cd ${PACKAGE_NAME}${NC}"
echo -e "${GREEN}./install.sh${NC}" 