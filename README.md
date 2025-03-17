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