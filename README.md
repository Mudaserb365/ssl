# Trust Store Management Tools

A comprehensive collection of scripts for managing trust stores across various environments and application frameworks.

## Scripts Overview

| Script | Description |
|--------|-------------|
| `app_trust_store_update.sh` | Updates application-specific trust stores for Node.js, Python, Ruby, Go, and .NET applications |
| `auto_trust_store_manager.sh` | Comprehensive script that automates discovery and modification of trust stores in various runtimes |
| `kubernetes-trust-store.yaml` | Kubernetes manifests for cluster-wide trust store management |

## Automated Trust Store Manager

The `auto_trust_store_manager.sh` script is the most comprehensive tool in this collection. It can:

- Discover trust stores in various formats (JKS, PKCS12, PEM)
- Determine if trust stores can be accessed without a password
- Try common default passwords
- Append certificates to trust stores
- Work with Docker containers and Kubernetes resources
- Log all operations and provide a summary

### Usage

```bash
./auto_trust_store_manager.sh [options]

Options:
  -d, --directory DIR       Target directory to scan (default: current directory)
  -c, --certificate FILE    Path to certificate to append (default: auto-generated)
  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)
  -p, --passwords "p1 p2"   Space-separated list of passwords to try (in quotes)
  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)
  -D, --docker              Enable Docker mode (scan common Docker trust store locations)
  -r, --restart             Restart affected services after modification
  -n, --no-backup           Disable backup creation before modification
  -v, --verbose             Enable verbose output
  -h, --help                Display this help message
```

### Examples

```bash
# Scan current directory for trust stores
./auto_trust_store_manager.sh

# Scan a specific directory with a custom certificate
./auto_trust_store_manager.sh -d /path/to/project -c /path/to/cert.pem

# Scan Kubernetes resources and restart affected services
./auto_trust_store_manager.sh --kubernetes --restart

# Scan Docker containers with verbose output
./auto_trust_store_manager.sh --docker -v

# Try specific passwords
./auto_trust_store_manager.sh -p "changeit password secret"
```

## Application Trust Store Update

The `app_trust_store_update.sh` script focuses specifically on updating trust stores for various application frameworks:

- Node.js: Updates `NODE_EXTRA_CA_CERTS` environment variable
- Python/Ruby/Go: Updates `SSL_CERT_FILE` environment variable
- .NET: Updates application configuration files

### Usage

```bash
./app_trust_store_update.sh [options]

Options:
  -s <path>    Path to standard trust store (default: /etc/ssl/certs/ca-certificates.crt)
  -d <path>    Application directory to scan (default: current directory)
  -m <mode>    Mode: 1=check, 2=update (default: 2)
  -u <url>     URL to download standard trust store
  -h           Display this help message
```

## Kubernetes Trust Store Management

The `kubernetes-trust-store.yaml` file provides Kubernetes manifests for:

- ConfigMap with CA certificates
- Init container script for trust store initialization
- Example deployment with proper trust store configuration
- CronJob for periodic trust store updates

### Usage

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