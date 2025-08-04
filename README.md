# Trust Store Management Tools

A comprehensive collection of tools for managing SSL/TLS trust stores across various environments and application frameworks. This project provides both **Bash scripts** and **Go software** implementations for automated trust store discovery, comparison, and management.

## 🏗️ Project Structure

This repository contains **two distinct, self-contained projects**:

| Project | Description | Best For |
|---------|-------------|----------|
| [`bash-trust-store-manager/`](./bash-trust-store-manager/) | **Shell-based tools** with broad compatibility | System administration, simple automation, legacy environments |
| [`go-trust-store-manager/`](./go-trust-store-manager/) | **Cross-platform binary** with advanced features | Enterprise environments, CI/CD pipelines, complex automation |

## 🚀 Quick Start

### Choose Your Implementation

**Option 1: Bash Scripts** (Universal compatibility)
```bash
cd bash-trust-store-manager
./auto_trust_store_manager.sh --help
```

**Option 2: Go Binary** (Advanced features)
```bash
cd go-trust-store-manager
./bin/trust-store-manager-darwin-arm64 --help  # Choose your platform
```

## 🎯 Core Capabilities

Both implementations provide identical core functionality:

- **🔍 Automatic Discovery**: Find trust stores in various formats (JKS, PKCS12, PEM)
- **📊 Baseline Comparison**: Compare trust stores against standard certificate bundles
- **🔄 Synchronized Updates**: Add/remove certificates consistently across environments
- **💾 Safe Operations**: Automatic backups before modifications
- **🔍 Dry-Run Mode**: Preview changes with `--noop` flag
- **🌐 Multi-Platform**: Support for Java, Python, Node.js, Docker, Kubernetes

### Advanced Features (Go Only)
- **🎛️ Interactive Mode**: Guided walkthrough for beginners
- **📡 Webhook Logging**: Enterprise monitoring and audit trails
- **🏗️ Project Detection**: Automatic runtime environment identification
- **⚡ Performance**: Optimized for large-scale operations

## 📚 Documentation

- **[Trust Store Management Guide](./trust-store-management.md)** - Comprehensive usage documentation
- **[Getting Started Guide](./starthere.md)** - Quick introduction and concepts

### Project-Specific Documentation
- **[Bash Implementation README](./bash-trust-store-manager/README.md)**
- **[Go Implementation README](./go-trust-store-manager/README.md)**
- **[Go Implementation Tutorial](./go-trust-store-manager/TUTORIAL.md)**
- **[Go Implementation Roadmap](./go-trust-store-manager/ROADMAP.md)**

## 🛠️ Installation

### Bash Scripts
```bash
cd bash-trust-store-manager
# Scripts are ready to use - no installation required
chmod +x *.sh
```

### Go Binary
```bash
cd go-trust-store-manager
./install.sh  # Install binary to your PATH
```

## 📖 Examples

### Dry-Run Mode (Preview Changes)
```bash
# Bash
./bash-trust-store-manager/auto_trust_store_manager.sh --noop -d /path/to/project -v

# Go  
./go-trust-store-manager/bin/trust-store-manager-darwin-arm64 --noop --auto -d /path/to/project -v
```

### Add Certificate to All Trust Stores
```bash
# Bash
./bash-trust-store-manager/auto_trust_store_manager.sh -d /path/to/project -c /path/to/cert.pem

# Go
./go-trust-store-manager/bin/trust-store-manager-darwin-arm64 --auto -d /path/to/project -c /path/to/cert.pem
```

### Interactive Walkthrough (Go Only)
```bash
./go-trust-store-manager/bin/trust-store-manager-darwin-arm64 --interactive
```

## 🔧 System Requirements

### Common Requirements
- **OpenSSL** - Certificate manipulation
- **Java keytool** - JKS trust store management (when working with Java keystores)

### Bash-Specific
- **Bash 4.0+**
- Standard Unix utilities (find, grep, etc.)

### Go-Specific  
- No additional dependencies (statically compiled binaries)

## 🌍 Environment Support

| Environment | Bash Scripts | Go Binary | Notes |
|-------------|--------------|-----------|-------|
| **Local Development** | ✅ | ✅ | Full feature support |
| **CI/CD Pipelines** | ✅ | ✅ | Automated operations |
| **Docker Containers** | ✅ | ✅ | Container-aware scanning |
| **Kubernetes Clusters** | ✅ | ✅ | ConfigMap and Secret support |
| **Cloud Platforms** | ✅ | ✅ | AWS, Azure, GCP compatible |
| **Legacy Systems** | ✅ | ⚠️ | Bash preferred for older systems |
| **Windows** | ⚠️ | ✅ | Go binary recommended |

## 🤝 Choosing Between Implementations

### Use **Bash Scripts** When:
- Working with legacy or restricted environments
- Need maximum compatibility across Unix-like systems
- Prefer simple, readable scripts that can be easily customized
- System administrators familiar with shell scripting
- Minimal dependencies required

### Use **Go Binary** When:
- Need enterprise features (webhooks, interactive mode)
- Working in modern development environments
- Require cross-platform compatibility (including Windows)
- Performance is important for large-scale operations
- Want a single, self-contained executable

## 🔐 Security Considerations

- Always validate certificate sources and URLs
- Use `--noop` mode to preview changes before execution
- Create backups before modifying production trust stores  
- Implement proper access controls for trust store management
- Monitor all trust store modifications via logging/webhooks

## 📝 License

MIT License - See individual project directories for specific details.

## 🤝 Contributing

Contributions are welcome! Please:
1. Choose the appropriate implementation (bash or go)
2. Follow the project-specific contribution guidelines
3. Test changes in both discovery and modification modes
4. Update relevant documentation

## 📞 Support

- **Issues**: Open GitHub issues for bugs or feature requests
- **Documentation**: Refer to project-specific README files
- **Examples**: Check the `examples/` directories in each project 