# Bash Trust Store Manager

A comprehensive collection of **shell scripts** for automated SSL/TLS trust store management across various environments. This implementation provides maximum compatibility and simplicity for system administrators and environments where bash scripting is preferred.

## Overview

The Bash Trust Store Manager provides reliable, easy-to-understand scripts for:
- **Discovering** trust stores in various formats (JKS, PKCS12, PEM)
- **Comparing** trust stores against baseline certificate bundles
- **Updating** trust stores with new certificates
- **Managing** trust stores across different runtime environments

## Project Structure

```
bash-trust-store-manager/
├── trust-store-manager.sh           # Main automation script
├── auto_trust_store_manager.sh      # Comprehensive legacy implementation
├── compare_and_update.sh            # Simplified comparison/update wrapper
├── app_trust_store_update.sh        # Application-specific trust store updates
├── compare_trust_stores.sh          # PEM trust store comparison utility
├── compare_jks_stores.sh            # JKS trust store comparison utility
├── docker_trust_store_*.sh          # Docker container trust store management
├── cf_trust_store_setup.sh          # AWS CloudFormation trust store setup
├── test_truststore.sh               # Trust store validation and testing
├── baseline-certs/                  # Reference certificate collection
├── project-*/                       # Runtime-specific example projects
├── examples/                        # Configuration examples and templates
├── ssl_test_website/                # SSL/TLS testing environment
└── test-suite/                      # Comprehensive test scenarios
```

## Quick Start

### Basic Usage

**1. Dry-Run Mode (Preview Changes)**
```bash
# Show what would be changed without making modifications
./trust-store-manager.sh --noop -d /path/to/project -v
```

**2. Update Trust Stores**
```bash
# Add certificate to all trust stores in a project
./trust-store-manager.sh -d /path/to/project -c /path/to/certificate.pem
```

**3. Compare Against Baseline**
```bash
# Compare trust stores with a baseline certificate bundle
./trust-store-manager.sh -b baseline-certs/baseline-trust-chain.pem -d /path/to/project -C
```

## Core Scripts

### 1. Main Automation Script (`trust-store-manager.sh`)

The primary tool for automated trust store discovery and management.

```bash
Usage: ./trust-store-manager.sh [options]

Core Options:
  -d, --directory DIR       Target directory to scan (default: current directory)
  -c, --certificate FILE    Path to certificate to append (default: auto-generated)
  -b, --baseline URL        URL to download baseline trust store for comparison
  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)
  -p, --passwords "p1 p2"   Space-separated list of passwords to try for JKS files

Operation Modes:
  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)
  -D, --docker              Enable Docker mode (scan common Docker locations)
  -C, --compare-only        Only compare trust stores, don't modify them
      --noop, --dry-run     Show what changes would be made without implementing them

Behavior Control:
  -r, --restart             Restart affected services after modification
  -n, --no-backup           Disable backup creation before modification
  -v, --verbose             Enable verbose output
  -h, --help                Display help message
```

### 2. Simplified Wrapper (`compare_and_update.sh`)

Easy-to-use script for common comparison and update operations.

```bash
# Compare and update all trust stores in the current project
./compare_and_update.sh

# Use custom baseline and directory
./compare_and_update.sh -b /path/to/baseline.pem -d /path/to/project

# Try specific passwords for JKS files
./compare_and_update.sh -p "password1 password2 password3"
```

### 3. Application-Specific Updates (`app_trust_store_update.sh`)

Specialized script for updating application-specific trust stores.

```bash
# Update trust stores for Node.js, Python, Ruby, Go, and .NET applications
./app_trust_store_update.sh -s /path/to/standard-trust-store.pem -d /path/to/projects
```

## Environment-Specific Scripts

### Docker Container Management
```bash
# Initialize trust stores in new containers
./docker_trust_store_init.sh -s /path/to/standard-trust-store.pem

# Update trust stores in running containers
./docker_trust_store_update.sh -s /path/to/standard-trust-store.pem -c container_id
```

### AWS CloudFormation
```bash
# Set up trust stores during EC2 instance launch
./cf_trust_store_setup.sh
```

### Trust Store Comparison
```bash
# Compare PEM trust stores
./compare_trust_stores.sh -s /path/to/standard.pem -t /path/to/target.pem

# Compare JKS trust stores
./compare_jks_stores.sh -s /path/to/standard.jks -t /path/to/target.jks -p changeit
```

## Example Projects

The repository includes complete example projects for different runtime environments:

### Java Projects (`project-java/`)
- Example JKS trust store configuration
- Java-specific update scripts
- Maven/Gradle integration examples

### Python Projects (`project-python/`)
- PEM trust store management for Python applications
- Virtual environment considerations
- pip/conda compatibility

### Node.js Projects (`project-nodejs/`)
- Certificate management for Node.js applications
- npm/yarn integration
- Environment variable configuration

### Nginx Configuration (`project-nginx/`)
- Web server trust store management
- SSL/TLS configuration examples
- Certificate reload procedures

## Installation & Setup

### Prerequisites
```bash
# Required tools
which openssl    # Certificate manipulation
which keytool    # Java KeyStore management (if working with JKS files)
which bash       # Bash 4.0 or higher

# Optional tools (for specific features)
which docker     # Docker mode support
which kubectl    # Kubernetes mode support
```

### Quick Setup
```bash
# 1. Clone or download the bash-trust-store-manager directory
# 2. Make scripts executable
chmod +x *.sh

# 3. Test installation
./trust-store-manager.sh --help
```

## Common Usage Patterns

### Development Workflow
```bash
# 1. Preview changes first
./trust-store-manager.sh --noop -d ./my-project -v

# 2. Execute changes if preview looks good
./trust-store-manager.sh -d ./my-project -v

# 3. Verify all trust stores are updated
./test_truststore.sh -d ./my-project
```

### CI/CD Integration
```bash
# Automated pipeline example
./trust-store-manager.sh \
  -b https://company.com/baseline-certs.pem \
  -d /app \
  --compare-only \
  --verbose
```

### Production Deployment
```bash
# Safe production update with backups
./trust-store-manager.sh \
  -d /production/app \
  -c /secure/new-certificate.pem \
  --verbose \
  --restart
```

## Configuration Examples

### Kubernetes Deployment (`examples/kubernetes-trust-store.yaml`)
Complete Kubernetes manifests for cluster-wide trust store management.

### Docker Compose (`examples/docker-compose-example.yml`)
Docker Compose configuration with trust store volume mounts.

### CloudFormation (`examples/cloudformation-example.yaml`)
AWS CloudFormation template with trust store initialization.

## Testing & Validation

### Test Suite
```bash
# Run comprehensive test suite
cd test-suite/
./run_validation_tests.sh

# Test specific trust store formats
./test_truststore.sh -f JKS -d ./test-keystores/
./test_truststore.sh -f PEM -d ./test-certificates/
```

### SSL Test Website
```bash
# Start local SSL testing environment
cd ssl_test_website/
docker-compose up

# Test certificate chain validation
curl -v https://localhost:8443/test
```

## Troubleshooting

### Common Issues

**JKS Password Problems**
```bash
# Try multiple passwords
./trust-store-manager.sh -p "changeit changeme password keystore secret"

# Check keystore info
keytool -list -keystore /path/to/keystore.jks
```

**Permission Issues**
```bash
# Ensure scripts are executable
chmod +x *.sh

# Check file permissions on trust stores
ls -la /path/to/truststore/
```

**Missing Dependencies**
```bash
# Install OpenSSL (Ubuntu/Debian)
sudo apt-get install openssl

# Install Java (for keytool)
sudo apt-get install default-jre

# Install Docker (if needed)
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
```

### Debug Mode
```bash
# Run with maximum verbosity
bash -x ./trust-store-manager.sh -v -d /path/to/project

# Check log files
tail -f trust_store_scan_*.log
```

## Security Best Practices

1. **Validate Sources**: Always verify certificate sources and baseline URLs
2. **Use Dry-Run**: Test with `--noop` before making changes
3. **Create Backups**: Keep `--backup` enabled (default) for production
4. **Access Control**: Restrict script execution to authorized users
5. **Audit Logging**: Enable verbose logging for audit trails

## System Requirements

### Minimum Requirements
- **Bash 4.0+**
- **OpenSSL** (any recent version)
- **Standard Unix utilities** (find, grep, awk, sed)

### Optional Requirements
- **Java Runtime** (for JKS trust store support)
- **Docker** (for container mode operations)
- **kubectl** (for Kubernetes mode operations)
- **curl/wget** (for downloading baseline certificates)

### Tested Platforms
- **Linux** (Ubuntu, CentOS, RHEL, Alpine)
- **macOS** (10.15+)
- **Unix variants** (FreeBSD, OpenBSD)
- **Windows** (WSL, Git Bash, Cygwin)

## Contributing

1. **Fork the project** and create a feature branch
2. **Test thoroughly** on multiple platforms
3. **Follow shell scripting best practices** (shellcheck compliance)
4. **Update documentation** for any new features
5. **Submit pull request** with clear description

## License

MIT License - Free for commercial and personal use.

## Support

- **Documentation**: See individual script help (`--help`)
- **Examples**: Check the `examples/` directory
- **Issues**: Report bugs or request features via GitHub issues
- **Testing**: Use the provided test suite for validation 