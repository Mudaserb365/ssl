# Trust Store Manager

A cross-platform tool for automating the discovery and modification of trust store files in various runtimes, containers, and web servers.

## Features

- **Automatic Detection**: Finds trust stores in your project automatically
- **Multiple Formats**: Supports JKS, PKCS12, and PEM certificate bundles
- **Interactive Mode**: Guided walkthrough to manage your trust stores
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **Project Detection**: Automatically identifies Java, Python, and Node.js projects

## Quick Start

### Interactive Mode (Recommended for First-Time Users)

Run the interactive script to get a guided walkthrough:

```bash
# macOS/Linux
./scripts/interactive_demo.sh

# Windows
bash scripts/interactive_demo.sh  # Requires Git Bash or similar
```

The interactive mode will:

1. Guide you through selecting a project directory
2. Automatically detect your project type (Java, Python, Node.js)
3. Help you configure trust store operations with sensible defaults
4. Execute trust store management based on your choices

### Command-Line Mode (For Automation)

Use the binary for your platform from the `bin` directory:

```bash
# macOS (Intel)
./bin/trust-store-manager-darwin-amd64 [options]

# macOS (Apple Silicon)
./bin/trust-store-manager-darwin-arm64 [options]

# Linux (Intel/AMD)
./bin/trust-store-manager-linux-amd64 [options]

# Linux (ARM)
./bin/trust-store-manager-linux-arm64 [options]

# Windows
./bin/trust-store-manager-windows-amd64.exe [options]
```

## Examples

### Finding Trust Stores in a Project

```bash
./bin/trust-store-manager-darwin-amd64 -d /path/to/project --compare-only
```

### Adding a Certificate to All Trust Stores

```bash
./bin/trust-store-manager-linux-amd64 -d /path/to/project -c /path/to/certificate.pem
```

### Using with Java Projects

```bash
./bin/trust-store-manager-linux-amd64 -d /path/to/java/project -p "changeit mypassword securepass"
```

## Installation

To install the Trust Store Manager, simply run:

```bash
./install.sh
```

This will:
1. Make all scripts and binaries executable
2. Create a symlink in a location of your choice (default: ~/.local/bin)
3. Provide instructions for adding the installation directory to your PATH if needed

## Project Types

The tool automatically detects the following project types:

- **Java**: Recognizes Maven (pom.xml), Gradle (build.gradle), JAR files
- **Python**: Identifies requirements.txt, setup.py, Pipfile, and Python code
- **Node.js**: Detects package.json, node_modules, JavaScript files

## Trust Store Formats

- **Java KeyStores (JKS)**: `.jks`, `.keystore`, `.truststore`
- **PKCS12**: `.p12`, `.pfx`
- **PEM Bundles**: `.pem`, `.crt`, `.cert`

## Support

For issues and feature requests, please visit:
https://github.com/mudaserb365/trust-store-manager 