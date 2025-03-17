# Trust Store Management Tools

A comprehensive collection of scripts for managing trust stores across various environments and application frameworks.

## Repository Structure

| Directory/File | Description |
|----------------|-------------|
| `app_trust_store_update.sh` | Updates application-specific trust stores for Node.js, Python, Ruby, Go, and .NET applications |
| `auto-trust-store-manager/` | Directory containing the comprehensive automated trust store management script |
| `kubernetes-trust-store.yaml` | Kubernetes manifests for cluster-wide trust store management |
| `trust-store-management.md` | Comprehensive documentation of trust store management use cases and permutations |

## Quick Start

### Automated Trust Store Manager

For the most comprehensive trust store management solution, use the Automated Trust Store Manager:

```bash
cd auto-trust-store-manager
./auto_trust_store_manager.sh
```

See the [dedicated README](auto-trust-store-manager/README.md) for detailed usage instructions.

### Application Trust Store Update

For updating application-specific trust stores:

```bash
./app_trust_store_update.sh [options]

Options:
  -s <path>    Path to standard trust store (default: /etc/ssl/certs/ca-certificates.crt)
  -d <path>    Application directory to scan (default: current directory)
  -m <mode>    Mode: 1=check, 2=update (default: 2)
  -u <url>     URL to download standard trust store
  -h           Display this help message
```

### Kubernetes Trust Store Management

For Kubernetes environments:

```bash
# Apply the Kubernetes manifests
kubectl apply -f kubernetes-trust-store.yaml
```

## Documentation

For a comprehensive guide on trust store management, including all possible permutations and use cases, see the [Trust Store Management Documentation](trust-store-management.md).

## Requirements

- Bash 4.0+
- OpenSSL
- Java keytool (for JKS trust stores)
- Docker (for Docker mode)
- kubectl (for Kubernetes mode)

## License

MIT 

# Auto Trust Store Manager

This project provides tools for automatically managing trust stores across different applications and platforms. It ensures that all trust stores in a project are kept in sync with a baseline trust chain.

## Components

- **Auto Trust Store Manager Script** (`auto_trust_store_manager.sh`): The core utility for discovering and updating trust stores
- **Compare and Update Script** (`compare_and_update.sh`): A wrapper script that uses the core utility to update all trust stores in a project

## Directory Structure

```
auto-trust-store-manager/
├── auto_trust_store_manager.sh     # Core utility script
├── compare_and_update.sh           # Wrapper script
├── baseline-certs/                 # Directory containing baseline certificates
│   ├── baseline-trust-chain.pem    # Baseline trust chain (PEM format)
│   ├── root-ca.crt                 # Root CA certificate
│   ├── intermediate-ca.crt         # Intermediate CA certificate
│   └── server.crt                  # Server certificate
├── project-java/                   # Example Java project
│   ├── update_java_truststore.sh   # Java-specific example script
│   └── truststore/
│       └── project-trust-store.jks # Java trust store (JKS format)
├── project-nodejs/                 # Example Node.js project
│   ├── update_nodejs_truststore.sh # Node.js-specific example script
│   └── truststore/
│       └── project-trust-chain.pem # Node.js trust store (PEM format)
└── project-python/                 # Example Python project
    ├── update_python_truststore.sh # Python-specific example script
    └── truststore/
        └── project-trust-chain.pem # Python trust store (PEM format)
```

## Auto Trust Store Manager Script

The `auto_trust_store_manager.sh` script is the core utility that discovers and updates trust stores in a project directory.

### Features

- Automatically discovers trust stores in various formats (PEM, JKS, etc.)
- Updates trust stores with certificates from a baseline trust chain
- Compares trust stores with a baseline to identify differences
- Handles various runtime environments (Java, Python, Node.js, etc.)
- Supports downloading baseline trust chain from a URL

### Command-Line Options

```
Usage: ./auto_trust_store_manager.sh [options]

Options:
  -d, --directory DIR       Target directory to scan (default: current directory)
  -b, --baseline FILE       Path to baseline trust chain for comparison/update
  -c, --certificate FILE    Path to certificate to append (default: auto-generated)
  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)
  -p, --passwords "p1 p2"   Space-separated list of passwords to try for JKS files (in quotes)
  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)
  -D, --docker              Enable Docker mode (scan common Docker trust store locations)
  -r, --restart             Restart affected services after modification
  -n, --no-backup           Disable backup creation before modification
  -v, --verbose             Enable verbose output
  -C, --compare-only        Only compare trust stores, don't modify them
  -u, --baseline-url URL    URL to download baseline trust chain for comparison
  -h, --help                Display this help message
```

### Examples

```bash
# Discover trust stores in a directory
./auto_trust_store_manager.sh -d /path/to/project -v

# Compare trust stores with a baseline
./auto_trust_store_manager.sh -b baseline-certs/baseline-trust-chain.pem -d /path/to/project -C -v

# Update trust stores with a baseline
./auto_trust_store_manager.sh -b baseline-certs/baseline-trust-chain.pem -d /path/to/project -v

# Try multiple passwords for JKS files
./auto_trust_store_manager.sh -b baseline-certs/baseline-trust-chain.pem -d /path/to/project -p "changeit changeme password" -v

# Download baseline from URL and update trust stores
./auto_trust_store_manager.sh -u https://example.com/baseline.pem -d /path/to/project -v
```

## Compare and Update Script

The `compare_and_update.sh` script is a wrapper around the core utility that simplifies the process of comparing and updating trust stores.

### Features

- Compares all trust stores in a project with a baseline trust chain
- Updates all trust stores to match the baseline
- Verifies that all trust stores match the baseline after update
- Handles JKS password issues by trying multiple common passwords

### Command-Line Options

```
Usage: ./compare_and_update.sh [options]

Options:
  -b, --baseline FILE       Path to baseline trust chain (default: baseline-certs/baseline-trust-chain.pem)
  -d, --directory DIR       Target directory to scan (default: current directory)
  -p, --passwords "p1 p2"   Space-separated list of passwords to try for JKS files (in quotes)
  -u, --baseline-url URL    URL to download baseline trust chain
  -v, --verbose             Enable verbose output
  -h, --help                Display this help message
```

### Examples

```bash
# Compare and update all trust stores in the project
./compare_and_update.sh

# Compare and update trust stores in a specific directory
./compare_and_update.sh -d /path/to/project

# Use a different baseline trust chain
./compare_and_update.sh -b /path/to/baseline.pem

# Try specific passwords for JKS files
./compare_and_update.sh -p "password1 password2 password3"

# Download baseline from URL and update trust stores
./compare_and_update.sh -u https://example.com/baseline.pem
```

## Runtime-Specific Examples

The project includes example scripts for updating trust stores in specific runtime environments:

### Java

```bash
# Update Java trust stores
./project-java/update_java_truststore.sh
```

### Python

```bash
# Update Python trust stores
./project-python/update_python_truststore.sh
```

### Node.js

```bash
# Update Node.js trust stores
./project-nodejs/update_nodejs_truststore.sh
```

## Using in CI/CD Pipelines

The scripts can be integrated into CI/CD pipelines to automatically update trust stores when new certificates are added to the baseline. This ensures that all applications in the project have the latest trusted certificates.

```bash
# Example CI/CD pipeline command
./compare_and_update.sh -b /path/to/baseline.pem -v
``` 