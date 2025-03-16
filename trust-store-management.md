# Trust Store Management: Comprehensive Use Cases and Permutations

## Introduction

This document outlines all possible permutations for updating trust stores in runtime environments. It serves as a comprehensive guide to the trust store management scripts in this repository.

## Core Use Cases

### 1. System-Level Trust Stores

| Environment | Script | Description |
|-------------|--------|-------------|
| Linux PEM/CRT/CERT | `compare_trust_stores.sh` | Updates system certificate stores in PEM format |
| Java JKS | `compare_jks_stores.sh` | Updates Java KeyStore files with password handling |
| Docker containers | `docker_trust_store_update.sh` | Updates trust stores in running Docker containers |
| CloudFormation | `cf_trust_store_setup.sh` | User data script for AWS EC2 instances |
| Kubernetes | `kubernetes-trust-store.yaml` | Kubernetes manifests for cluster-wide trust store management |

### 2. Application-Specific Trust Stores

| Application Type | Script | Environment Variable |
|------------------|--------|---------------------|
| Node.js | `app_trust_store_update.sh` | `NODE_EXTRA_CA_CERTS` |
| Python | `app_trust_store_update.sh` | `SSL_CERT_FILE` |
| Ruby | `app_trust_store_update.sh` | `SSL_CERT_FILE` |
| Go | `app_trust_store_update.sh` | `SSL_CERT_FILE` |
| .NET | `app_trust_store_update.sh` | Configuration in appsettings.json |

## Implementation Permutations

### 1. Trust Store Types

| Trust Store Type | Format | Tools | Special Considerations |
|------------------|--------|-------|------------------------|
| System CA bundle | PEM/CRT/CERT | OpenSSL, update-ca-certificates | OS-specific locations |
| Java KeyStore | JKS | keytool | Password protection, alias management |
| PKCS#12 | P12/PFX | OpenSSL | Password protection, private key handling |
| Windows Certificate Store | System store | certutil | Registry-based, requires admin rights |
| Application-specific | Various | Custom scripts | Application restart may be required |
| NSS databases | cert8.db, cert9.db | certutil | Used by Firefox, Thunderbird |

### 2. Update Mechanisms

| Mechanism | Pros | Cons | Best For |
|-----------|------|------|----------|
| File replacement | Simple, direct | May require service restart | Static environments |
| Certificate append | Non-destructive | May accumulate outdated certs | Production systems |
| Scheduled updates | Automated maintenance | Requires scheduler | Long-running systems |
| Event-driven updates | Real-time response | Complex setup | Critical systems |
| Init-time only | Simple deployment | No runtime updates | Immutable infrastructure |
| Sidecar container | Isolation, dedicated | Resource overhead | Kubernetes environments |

### 3. Distribution Methods

| Method | Description | Best For |
|--------|-------------|----------|
| Central HTTP(S) endpoint | Pull from central server | Cross-platform compatibility |
| Git repository | Version-controlled certificates | DevOps-oriented teams |
| Configuration management | Ansible, Chef, Puppet | Enterprise environments |
| Secret management | Vault, AWS Secrets Manager | Sensitive certificates |
| Package repository | OS package manager | System-level trust stores |
| Container registry | Custom base images | Container-based deployments |

## Deployment Scenarios

### 1. Local Development Environment

```bash
# Update system trust stores
./compare_trust_stores.sh -s /path/to/standard-trust-store.pem -m 2

# Update JKS trust stores
./compare_jks_stores.sh -s /path/to/standard-trust-store.jks -p changeit -m 2

# Update application-specific trust stores
./app_trust_store_update.sh -s /path/to/standard-trust-store.pem -d /path/to/projects -m 2
```

### 2. Docker Environment

```bash
# Update trust stores in a running container
./docker_trust_store_update.sh -s /path/to/standard-trust-store.pem -c container_id -m 2

# Use in Docker Compose
# See docker-compose-example.yml for a complete example
```

### 3. Cloud Environment

```bash
# AWS CloudFormation
# See cloudformation-example.yaml for a complete example

# Kubernetes
# See kubernetes-trust-store.yaml for a complete example
```

## Common Patterns and Best Practices

### 1. Trust Store Management Lifecycle

1. **Initialization**: Set up trust stores during system/container startup
2. **Monitoring**: Regularly check for trust store updates
3. **Update**: Apply updates using the appropriate script
4. **Verification**: Validate that applications can establish secure connections
5. **Rotation**: Remove outdated certificates

### 2. Security Considerations

- Always validate the source of trust store updates
- Use HTTPS for downloading trust stores
- Consider using cryptographic signatures to verify trust store integrity
- Implement proper access controls for trust store management scripts
- Create backups before making changes to trust stores

### 3. Operational Considerations

- Schedule updates during maintenance windows when possible
- Implement proper logging and monitoring for trust store updates
- Have a rollback plan in case of issues
- Test updates in a staging environment before applying to production
- Consider the impact on running applications (some may require restart)

## Troubleshooting

### 1. Common Issues

| Issue | Possible Causes | Solutions |
|-------|----------------|-----------|
| Certificate not trusted | Trust store not updated | Run appropriate update script |
| | Application not using system trust store | Configure application to use updated trust store |
| | Application requires restart | Restart application after trust store update |
| JKS password issues | Incorrect password | Try default passwords (changeit, password) |
| | Password not specified | Use `-p` parameter with correct password |
| Docker container issues | Container filesystem read-only | Mount volume for certificates |
| | Container lacks required tools | Use appropriate base image or install tools |
| Kubernetes issues | Pod security policies | Configure appropriate permissions |
| | Init container failures | Check init container logs |

### 2. Debugging Tools

- `openssl verify`: Verify certificate against a trust store
- `keytool -list`: List certificates in a JKS trust store
- `curl --verbose`: Show certificate verification details
- `strace`: Trace system calls to see which certificate files are being accessed

## Conclusion

This comprehensive guide covers all aspects of trust store management across different environments and application types. By following these patterns and using the provided scripts, you can ensure that your systems maintain up-to-date trust stores, enhancing security and preventing certificate-related issues. 