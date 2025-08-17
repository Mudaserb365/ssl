# Trust Store Manager - Demo Quick Start Guide

## Demo Materials Overview

This directory contains a comprehensive demonstration of the Trust Store Manager tool with real examples, sample trust stores, and step-by-step scenarios.

### Files Available

1. **`trust-store-manager-demo.md`** - Complete interactive demo with 5 detailed scenarios
2. **`demo-quick-start.md`** - This quick reference guide
3. **`demo-materials/`** - Sample trust stores and certificates for hands-on testing

### Demo Materials Structure

```
demo-materials/
├── source-truststore/
│   └── app-truststore.jks          # Sample JKS application trust store
├── destination-truststore/
│   └── client-truststore.jks       # Sample JKS client trust store  
└── baseline-certs/
    ├── basic-trust-store.pem       # Single certificate PEM bundle
    ├── multi-cert-trust-store.pem  # Multiple certificate PEM bundle
    ├── large-trust-store.pem       # Performance testing PEM bundle
    ├── test-ca.pem                 # Test CA certificate
    └── [additional certificate files]
```

## Quick Demo Commands

### 1. Discovery Mode (Safe - No Changes)
```bash
# Discover trust stores in demo materials
./go-trust-store-manager/bin/trust-store-manager-darwin-arm64 \
  --noop --auto -d ./demo-materials -v
```

### 2. Certificate Addition
```bash
# Add a certificate to all trust stores
./go-trust-store-manager/bin/trust-store-manager-darwin-arm64 \
  --auto -d ./demo-materials \
  -c ./demo-materials/baseline-certs/test-ca.pem -v
```

### 3. Baseline Comparison
```bash
# Compare against baseline (no changes)
./go-trust-store-manager/bin/trust-store-manager-darwin-arm64 \
  --compare-only \
  -b ./demo-materials/baseline-certs/multi-cert-trust-store.pem \
  -d ./demo-materials -v
```

### 4. Interactive Mode
```bash
# Run guided interactive demo
./go-trust-store-manager/bin/trust-store-manager-darwin-arm64 --interactive
```

## JKS Trust Store Information

**Default Password:** `changeit`

**View Contents:**
```bash
# View JKS trust store contents
keytool -list -keystore ./demo-materials/source-truststore/app-truststore.jks \
  -storepass changeit
```

## Demo Scenarios Covered

1. **Discovery and Assessment** - Find and catalog trust stores
2. **Certificate Addition** - Add new certificates across formats
3. **Baseline Synchronization** - Ensure compliance with corporate standards
4. **Multi-Format Management** - Handle JKS, PEM, PKCS12 simultaneously  
5. **Enterprise Monitoring** - Structured logging and audit trails

## Safety Features Demonstrated

- ✅ **Dry-run mode** (`--noop`) - Preview changes without applying
- ✅ **Automatic backups** - All modifications create `.bak` files
- ✅ **Password detection** - Attempts common JKS passwords automatically
- ✅ **Format validation** - Verifies certificate integrity before import
- ✅ **Rollback capability** - Restore from backups if needed

## Expected Log Output Preview

```log
[NOOP] Running in dry-run mode - no changes will be made
[INFO] Trust Store Scan started - 2025-08-05 12:16:31
[SUCCESS] Found keytool in PATH: /usr/bin/keytool
[INFO] Scanning directory: ./demo-materials
[INFO] Found potential trust stores
[INFO] Processing trust store: ./demo-materials/source-truststore/app-truststore.jks (Type: JKS)
[INFO] Processing trust store: ./demo-materials/destination-truststore/client-truststore.jks (Type: JKS)
...
```

## Next Steps

1. **Read the full demo:** `trust-store-manager-demo.md`
2. **Run discovery scan:** Start with `--noop` mode for safety
3. **Try certificate addition:** Use sample certificate files
4. **Explore interactive mode:** For guided experience
5. **Check backups:** Verify `.bak` files are created after operations

## Platform-Specific Binaries

Choose the appropriate binary for your system:
- **macOS Apple Silicon:** `trust-store-manager-darwin-arm64`
- **macOS Intel:** `trust-store-manager-darwin-amd64`
- **Linux x64:** `trust-store-manager-linux-amd64`
- **Linux ARM64:** `trust-store-manager-linux-arm64`
- **Windows x64:** `trust-store-manager-windows-amd64.exe`

## Troubleshooting

- **Java not found:** Install JDK/JRE or set `JAVA_HOME`
- **Permission denied:** Use `chmod +x` on binaries
- **Wrong architecture:** Choose correct binary for your platform

---

*Quick start guide for Trust Store Manager Demo*
