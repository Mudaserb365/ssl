#!/bin/bash
# Build script for Trust Store Manager

set -e

VERSION="1.0.0"
BINARY_NAME="trust-store-manager"
BUILD_DIR="./build"

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Function to build the application for a specific platform
build_for_platform() {
    local os=$1
    local arch=$2
    local extension=$3
    
    echo "Building for $os/$arch..."
    
    # Set environment variables for cross-compilation
    export GOOS=$os
    export GOARCH=$arch
    
    # Build the binary
    if [ "$os" = "windows" ]; then
        go build -ldflags="-s -w" -o "$BUILD_DIR/${BINARY_NAME}-${VERSION}-${os}-${arch}${extension}"
    else
        go build -ldflags="-s -w" -o "$BUILD_DIR/${BINARY_NAME}-${VERSION}-${os}-${arch}${extension}"
    fi
    
    echo "Done building for $os/$arch"
}

# Clean up previous builds
echo "Cleaning up previous builds..."
rm -rf "$BUILD_DIR"/*

# Build for various platforms
build_for_platform "linux" "amd64" ""
build_for_platform "linux" "arm64" ""
build_for_platform "windows" "amd64" ".exe"
build_for_platform "darwin" "amd64" ""
build_for_platform "darwin" "arm64" ""

echo "All builds completed successfully!"
echo "Binaries are available in the $BUILD_DIR directory." 