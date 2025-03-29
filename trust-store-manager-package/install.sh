#!/bin/bash

# Trust Store Manager Installation Script
# This script makes the binaries executable and creates symlinks in a user-accessible location

# Colors for better UI
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Detect OS and architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

if [[ "$ARCH" == "x86_64" ]]; then
  ARCH="amd64"
elif [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
  ARCH="arm64"
else
  ARCH="amd64" # Default to amd64 if unknown
fi

# Determine which binary to use
if [[ "$OS" == "darwin" ]]; then
  BINARY="bin/trust-store-manager-darwin-$ARCH"
elif [[ "$OS" == "linux" ]]; then
  BINARY="bin/trust-store-manager-linux-$ARCH"
elif [[ "$OS" =~ windows ]]; then
  BINARY="bin/trust-store-manager-windows-amd64.exe"
else
  echo -e "${RED}Unsupported operating system: $OS${NC}"
  exit 1
fi

# Make scripts executable
echo -e "${BLUE}Making scripts executable...${NC}"
chmod +x scripts/*.sh
chmod +x bin/*

# Verify the binary for this system exists
if [[ ! -f "$BINARY" ]]; then
  echo -e "${RED}Error: Binary not found: $BINARY${NC}"
  echo -e "${YELLOW}The package might be incomplete or corrupted.${NC}"
  exit 1
fi

# Create symlink location
echo -e "${BLUE}Setting up Trust Store Manager...${NC}"

# Determine installation location
DEFAULT_INSTALL_DIR="$HOME/.local/bin"
echo -e "${YELLOW}Where would you like to install the Trust Store Manager?${NC}"
echo -e "Default: $DEFAULT_INSTALL_DIR"
echo -e "Press Enter to accept default or provide a different path:"
read INSTALL_DIR

if [[ -z "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$DEFAULT_INSTALL_DIR"
fi

# Create the directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

if [[ ! -d "$INSTALL_DIR" ]]; then
  echo -e "${RED}Failed to create directory: $INSTALL_DIR${NC}"
  exit 1
fi

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="$SCRIPT_DIR/$BINARY"
INSTALL_PATH="$INSTALL_DIR/trust-store-manager"

# Create the symlink
echo -e "${BLUE}Creating symlink at $INSTALL_PATH...${NC}"
ln -sf "$BINARY_PATH" "$INSTALL_PATH"

if [[ $? -ne 0 ]]; then
  echo -e "${RED}Failed to create symlink.${NC}"
  exit 1
fi

# Verify the PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo -e "${YELLOW}Warning: $INSTALL_DIR is not in your PATH.${NC}"
  echo -e "${YELLOW}Add the following line to your shell profile (.bashrc, .zshrc, etc.):${NC}"
  echo -e "${GREEN}export PATH=\"\$PATH:$INSTALL_DIR\"${NC}"
  echo
fi

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}Trust Store Manager installed successfully!${NC}"
echo -e "${GREEN}=======================================${NC}"
echo
echo -e "${BLUE}You can now run it using the following command:${NC}"
echo -e "${GREEN}trust-store-manager [options]${NC}"
echo
echo -e "${BLUE}For interactive mode, run:${NC}"
echo -e "${GREEN}$SCRIPT_DIR/scripts/interactive_demo.sh${NC}"
echo
echo -e "${BLUE}For more information, see the README.md file.${NC}" 