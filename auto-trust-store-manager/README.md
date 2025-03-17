# Automated Trust Store Manager

A comprehensive script that automates the discovery and modification of trust store files in various runtimes, containers, and web servers.

## Features

- **Automatic Discovery**: Finds trust stores in various formats (JKS, PKCS12, PEM)
- **Password Handling**: Tries common default passwords for accessing protected trust stores
- **Multiple Environments**:
  - Local filesystem
  - Docker containers
  - Kubernetes resources (ConfigMaps and Secrets)
- **Configuration Parsing**: Extracts trust store paths from various configuration files
- **Backup Creation**: Creates backups before modifying trust stores
- **Detailed Logging**: Provides comprehensive logs of all operations
- **Service Restart**: Optionally restarts affected services after modification

## Supported Trust Store Types

- Java KeyStore (JKS) files (`.jks`, `.keystore`, `.truststore`)
- PKCS#12 files (`.p12`, `.pfx`)
- PEM certificate bundles (`.pem`, `.crt`, `.cer`, `.cert`)

## Supported Environments

- JVM-based runtimes: Java, Spring Boot, Tomcat, JBoss/WildFly, WebLogic, WebSphere
- Containers: Docker, Kubernetes
- Web Servers: Nginx, Apache HTTPD
- Other runtimes: Node.js, Python, Go applications

## Usage

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

## Examples

### Basic Usage

```bash
# Scan current directory for trust stores
./auto_trust_store_manager.sh

# Scan a specific directory with a custom certificate
./auto_trust_store_manager.sh -d /path/to/project -c /path/to/cert.pem

# Enable verbose output
./auto_trust_store_manager.sh -v
```

### Docker Mode

```bash
# Scan Docker containers for trust stores
./auto_trust_store_manager.sh --docker

# Scan Docker containers and restart them after modification
./auto_trust_store_manager.sh --docker --restart
```

### Kubernetes Mode

```bash
# Scan Kubernetes resources for trust stores
./auto_trust_store_manager.sh --kubernetes

# Scan Kubernetes resources with custom passwords
./auto_trust_store_manager.sh --kubernetes -p "changeit password secret"
```

## How It Works

1. **Discovery Phase**:
   - Searches for trust store files by extension
   - Extracts trust store paths from configuration files
   - In Docker mode, scans common trust store locations in containers
   - In Kubernetes mode, scans ConfigMaps and Secrets

2. **Access Phase**:
   - Determines the type of each trust store
   - For protected stores, tries common passwords
   - Creates backups before modification

3. **Modification Phase**:
   - Appends the specified certificate to each trust store
   - Verifies the modification was successful
   - Logs the results

4. **Cleanup Phase**:
   - Restarts services if requested
   - Prints a summary of operations

## Requirements

- Bash 4.0+
- OpenSSL
- Java keytool (for JKS trust stores)
- Docker (for Docker mode)
- kubectl and jq (for Kubernetes mode)

## Troubleshooting

### Common Issues

- **Missing Dependencies**: Ensure all required tools are installed
- **Permission Issues**: The script may need elevated privileges to access certain trust stores
- **Password Issues**: If your trust stores use non-standard passwords, specify them with the `-p` option

### Log File

The script creates a detailed log file that includes:
- All discovered trust stores
- Access attempts and results
- Modification status
- Commands to remove test certificates if needed

## License

MIT 