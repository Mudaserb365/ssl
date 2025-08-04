# Trust Store Manager Tutorial

This tutorial guides you through common trust store management operations using the Trust Store Manager tool.

## Prerequisites

- Trust Store Manager installed (run `./install.sh` if you haven't done so)
- Basic understanding of SSL/TLS certificates and trust stores

## Basic Operations

### 1. Scanning for Trust Stores

To find all trust stores in a project directory without modifying them:

```bash
trust-store-manager -d /path/to/project --scan-only
```

This will:
- Recursively search the specified directory
- Identify Java KeyStores, PKCS12 files, and PEM certificate bundles
- Display the location and type of each trust store found

### 2. Adding a Certificate to Trust Stores

To add a certificate to all trust stores in a project:

```bash
trust-store-manager -d /path/to/project -c /path/to/certificate.pem
```

This will:
- Find all trust stores in the specified directory
- Add the certificate to each trust store
- Preserve existing certificates in the trust stores

For Java KeyStores (JKS), you may need to specify passwords:

```bash
trust-store-manager -d /path/to/project -c /path/to/certificate.pem -p "changeit otherpassword"
```

### 3. Comparing Trust Stores with a Baseline

To check if trust stores match a baseline certificate bundle:

```bash
trust-store-manager -d /path/to/project -b /path/to/baseline.pem --compare-only
```

This will:
- Compare each trust store with the baseline
- Report differences (missing or additional certificates)
- Not modify any trust stores

### 4. Updating Trust Stores to Match a Baseline

To make all trust stores match a baseline certificate bundle:

```bash
trust-store-manager -d /path/to/project -b /path/to/baseline.pem
```

This will:
- Add missing certificates from the baseline to each trust store
- Remove certificates not in the baseline (if found in trust stores)
- Ensure all trust stores have the same certificate content

## Advanced Usage

### Working with Java Projects

Java projects typically use JKS files with passwords:

```bash
trust-store-manager -d /path/to/java/project -p "changeit mypassword securepass"
```

The tool will try each password with each JKS file until one works.

### Working with Container Projects

For Docker or Kubernetes projects:

```bash
trust-store-manager -d /path/to/container/project --container-aware
```

This will identify trust stores used in container configurations and update them appropriately.

### Using Environment Variables

You can use environment variables for sensitive values:

```bash
export JKS_PASSWORDS="changeit securepass"
trust-store-manager -d /path/to/project --env-passwords
```

## Troubleshooting

### Common Issues

1. **Unable to open JKS files**
   - Ensure you've provided the correct passwords with the `-p` option
   - Check if the JKS file is corrupted

2. **Certificate not recognized**
   - Ensure the certificate is in PEM format
   - Check if the certificate has proper headers and formatting

3. **Trust store not found**
   - The tool might not recognize your trust store format
   - Try specifying the trust store directly: `-t /path/to/truststore`

### Getting Help

For more detailed help on any command:

```bash
trust-store-manager --help
```

## Next Steps

- Try the interactive mode: `./scripts/interactive_demo.sh`
- Explore the examples in the `examples/` directory
- Set up continuous integration for trust store management 