#!/bin/bash

# SSL Certificate Inspector - Local Test Script
# This script tests the application locally before containerization

set -e

echo "🔍 SSL Certificate Inspector - Local Test"
echo "========================================"

# Check if we have the required files
echo "📁 Checking project files..."
required_files=("index.html" "cert-analyzer.js" "nginx.conf" "Dockerfile" "docker-compose.yml")

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (missing)"
        exit 1
    fi
done

# Check if Docker is available
echo ""
echo "🐳 Checking Docker availability..."
if command -v docker &> /dev/null; then
    echo "  ✅ Docker is installed"
    docker_version=$(docker --version)
    echo "  📝 $docker_version"
else
    echo "  ❌ Docker is not installed"
    echo "  💡 You can still test with a local web server"
fi

# Check if docker-compose is available
if command -v docker-compose &> /dev/null; then
    echo "  ✅ Docker Compose is installed"
    compose_version=$(docker-compose --version)
    echo "  📝 $compose_version"
else
    echo "  ⚠️  Docker Compose not available (using 'docker compose' instead)"
fi

echo ""
echo "🌐 Testing options available:"
echo ""

# Option 1: Python HTTP Server
if command -v python3 &> /dev/null; then
    echo "Option 1: Python HTTP Server"
    echo "  Command: python3 -m http.server 8000"
    echo "  URL: http://localhost:8000"
    echo ""
fi

# Option 2: Node.js serve
if command -v npx &> /dev/null; then
    echo "Option 2: Node.js serve"
    echo "  Command: npx serve . -p 8000"
    echo "  URL: http://localhost:8000"
    echo ""
fi

# Option 3: Docker
if command -v docker &> /dev/null; then
    echo "Option 3: Docker Container"
    echo "  Commands:"
    echo "    docker build -t ssl-certificate-inspector ."
    echo "    docker run -d -p 8080:80 --name ssl-inspector ssl-certificate-inspector"
    echo "  URL: http://localhost:8080"
    echo ""
fi

# Option 4: Docker Compose
if command -v docker-compose &> /dev/null || command -v docker &> /dev/null; then
    echo "Option 4: Docker Compose (Recommended)"
    echo "  Command: docker-compose up -d"
    echo "  URL: http://localhost:8080"
    echo "  Health Check: http://localhost:8080/health"
    echo ""
fi

# Ask user what they want to do
echo "🚀 Quick Start Options:"
echo "1) Start with Python HTTP Server (port 8000)"
echo "2) Build and run Docker container (port 8080)"
echo "3) Run with Docker Compose (port 8080)"
echo "4) Just show me the file structure"
echo "5) Exit"
echo ""

read -p "Choose an option (1-5): " choice

case $choice in
    1)
        if command -v python3 &> /dev/null; then
            echo "🌐 Starting Python HTTP Server..."
            echo "📡 Open http://localhost:8000 in your browser"
            echo "🛑 Press Ctrl+C to stop"
            python3 -m http.server 8000
        else
            echo "❌ Python3 not available"
            exit 1
        fi
        ;;
    2)
        if command -v docker &> /dev/null; then
            echo "🐳 Building Docker image..."
            docker build -t ssl-certificate-inspector .
            echo "🚀 Starting container..."
            docker run -d -p 8080:80 --name ssl-inspector ssl-certificate-inspector
            echo "✅ Container started!"
            echo "📡 Open http://localhost:8080 in your browser"
            echo "🏥 Health check: http://localhost:8080/health"
            echo ""
            echo "📊 Container status:"
            docker ps | grep ssl-inspector
            echo ""
            echo "🛑 To stop: docker stop ssl-inspector && docker rm ssl-inspector"
        else
            echo "❌ Docker not available"
            exit 1
        fi
        ;;
    3)
        if command -v docker-compose &> /dev/null; then
            echo "🐳 Starting with Docker Compose..."
            docker-compose up -d
            echo "✅ Services started!"
            echo "📡 Open http://localhost:8080 in your browser"
            echo "🏥 Health check: http://localhost:8080/health"
            echo ""
            echo "📊 Service status:"
            docker-compose ps
            echo ""
            echo "🛑 To stop: docker-compose down"
        else
            echo "❌ Docker Compose not available"
            exit 1
        fi
        ;;
    4)
        echo "📁 Project structure:"
        echo ""
        tree -a . 2>/dev/null || ls -la
        echo ""
        echo "📝 File sizes:"
        du -h * 2>/dev/null || echo "File size information not available"
        ;;
    5)
        echo "👋 Goodbye!"
        exit 0
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

echo ""
echo "✨ SSL Certificate Inspector test completed!" 