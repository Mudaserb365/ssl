# Go Trust Store Manager

A **high-performance, cross-platform binary** for automated SSL/TLS trust store management. Built in Go for enterprise environments requiring advanced features, scalability, and cross-platform compatibility.

## 🎯 Overview

The Go Trust Store Manager provides:
- **🚀 Performance**: Optimized for large-scale operations and enterprise environments
- **🎛️ Interactive Mode**: Guided walkthrough with automatic project detection
- **📡 Enterprise Features**: Webhook logging, centralized monitoring, audit trails
- **🌍 Cross-Platform**: Native binaries for Linux, macOS, Windows (x64/ARM64)
- **⚡ Zero Dependencies**: Self-contained executables with no external requirements

## 📁 Project Structure

```
go-trust-store-manager/
├── bin/                              # 🔧 Pre-compiled binaries for all platforms
│   ├── trust-store-manager-darwin-amd64
│   ├── trust-store-manager-darwin-arm64
│   ├── trust-store-manager-linux-amd64
│   ├── trust-store-manager-linux-arm64
│   └── trust-store-manager-windows-amd64.exe
├── main.go                           # 🎯 Main application entry point
├── handler.go                        # 🔄 Trust store processing logic
├── scanner.go                        # 🔍 Trust store discovery engine
├── certificate.go                    # 📜 Certificate manipulation utilities
├── utils.go                          # 🛠️ Common utility functions
├── build.sh                          # 🏗️ Cross-platform build script
├── Makefile                          # 📋 Build automation
├── go.mod                            # 📦 Go module definition
├── examples/                         # 📚 Usage examples and integrations
├── scripts/                          # 🔧 Helper scripts and demos
├── test_keystores/                   # 🧪 Test certificates and keystores
├── README.md                         # 📖 This documentation
├── TUTORIAL.md                       # 🎓 Step-by-step usage guide
├── ROADMAP.md                        # 🗺️ Future development plans
├── RELEASE_NOTES.md                  # 📋 Version history and changes
├── install.sh                        # ⚙️ Installation script
└── package.sh                        # 📦 Distribution packaging script
```

## 🚀 Quick Start

### Installation

**Option 1: Use Installation Script**
```bash
./install.sh
# Follow prompts to install binary to your PATH
```

**Option 2: Direct Binary Usage**
```bash
# Choose the binary for your platform
./bin/trust-store-manager-darwin-arm64 --help    # macOS Apple Silicon
./bin/trust-store-manager-darwin-amd64 --help    # macOS Intel
./bin/trust-store-manager-linux-amd64 --help     # Linux x64
./bin/trust-store-manager-linux-arm64 --help     # Linux ARM64
./bin/trust-store-manager-windows-amd64.exe      # Windows x64
```

### Basic Usage

**1. Interactive Mode (Recommended for First-Time Users)**
```bash
./bin/trust-store-manager-darwin-arm64 --interactive
```
- Automatic project type detection (Java, Python, Node.js)
- Guided configuration with sensible defaults
- Step-by-step walkthrough of all options

**2. Dry-Run Mode (Preview Changes)**
```bash
./bin/trust-store-manager-darwin-arm64 --noop --auto -d /path/to/project -v
```

**3. Automated Mode (CI/CD & Scripting)**
```bash
./bin/trust-store-manager-darwin-arm64 --auto -d /path/to/project -c /path/to/cert.pem
```

## 🛠️ Command Reference

### Core Operation Flags
```bash
Usage: trust-store-manager [options]

Project & Files:
  -d, --directory DIR       Target directory to scan (default: current directory)
  -c, --certificate FILE    Path to certificate to append (default: auto-generated)
  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)
  -b, --baseline URL        URL to download baseline trust store for comparison

Security & Passwords:
  -p, --passwords "p1 p2"   Space-separated list of passwords to try for JKS files (in quotes)

Operation Modes:
  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)
  -D, --docker              Enable Docker mode (scan common Docker locations)
  -C, --compare-only        Only compare trust stores, don't modify them
      --noop, --dry-run     Show what changes would be made without implementing them

Execution Control:
      --interactive         Run in interactive walkthrough mode (default if no args)
      --auto                Run in automatic mode (non-interactive)
  -r, --restart             Restart affected services after modification
  -n, --no-backup           Disable backup creation before modification
  -v, --verbose             Enable verbose output
  -h, --help                Display this help message

Enterprise Features:
      --webhook             Enable webhook logging for centralized monitoring
      --webhook-url URL     URL to send logs to (e.g., https://logs.company.com/api)
      --webhook-key KEY     API key for webhook authentication
```

## 🎛️ Interactive Mode Features

### Automatic Project Detection
The tool analyzes your project directory and automatically detects:

- **Java Projects**: Maven (`pom.xml`), Gradle (`build.gradle`), JAR files
- **Python Projects**: `requirements.txt`, `setup.py`, `Pipfile`, virtual environments
- **Node.js Projects**: `package.json`, `node_modules`, TypeScript files

### Guided Configuration
```
=== Trust Store Manager Interactive Walkthrough ===
This wizard will guide you through the process of managing trust stores in your project.

Enter the project directory path [/current/directory]: 
Analyzing project directory...
Detected java project. Continue with this project type? [y/N]: y

Configuring options for java project...
Select scan mode:
1. Discovery only - Find and report trust stores without modifications
2. Update existing - Update only existing trust stores  
3. Comprehensive - Find, create, and update trust stores
Enter your choice (1-3) [1]: 2

=== Configuration Summary ===
Project directory: /path/to/project
Project type: java
Scan mode: update
Certificate: Auto-generated
JKS passwords: changeit, mypassword
Verbose mode: true
Create backups: true

Proceed with these settings? [y/N]: y
```

## 🌐 Advanced Features

### Webhook Logging & Enterprise Monitoring

Perfect for enterprise environments requiring centralized audit trails:

```bash
# Enable webhook logging with authentication
./bin/trust-store-manager-linux-amd64 \
  --webhook \
  --webhook-url https://logs.company.com/api/trust-store \
  --webhook-key your-api-key \
  --auto -d /production/app
```

**Webhook JSON Format:**
```json
{
  "timestamp": "2023-03-29T15:30:45Z",
  "level": "SUCCESS",
  "message": "Successfully imported certificate to /app/truststore.jks",
  "host": {
    "hostname": "prod-server-01", 
    "ip_addresses": ["10.0.1.100"],
    "os": "linux",
    "arch": "amd64"
  },
  "metadata": {
    "certificate_count": 75,
    "operation": "import",
    "file_type": "JKS"
  }
}
```

### Container & Cloud Platform Support

**Docker Mode:**
```bash
# Scan Docker containers for trust stores
./bin/trust-store-manager-linux-amd64 --docker --auto -v
```

**Kubernetes Mode:**
```bash
# Scan Kubernetes ConfigMaps and Secrets
./bin/trust-store-manager-linux-amd64 --kubernetes --auto -v
```

## 📖 Usage Examples

### Development Workflows

**1. Local Development - Interactive Setup**
```bash
# Start interactive mode for guided setup
./bin/trust-store-manager-darwin-arm64 --interactive
```

**2. Code Review - Preview Changes**
```bash
# Show what would be changed in a pull request
./bin/trust-store-manager-linux-amd64 \
  --noop --auto \
  -d ./feature-branch \
  -c ./new-certificate.pem \
  --verbose
```

**3. Production Deployment - Safe Updates**
```bash
# Update production with full logging and webhooks
./bin/trust-store-manager-linux-amd64 \
  --auto \
  -d /production/app \
  -c /secure/certificates/new-cert.pem \
  --webhook --webhook-url https://audit.company.com/api \
  --verbose \
  --restart
```

### CI/CD Pipeline Integration

**GitHub Actions Example:**
```yaml
- name: Update Trust Stores
  run: |
    ./go-trust-store-manager/bin/trust-store-manager-linux-amd64 \
      --auto \
      --noop \
      -d ./application \
      -b https://company.com/baseline-certs.pem \
      --verbose
```

**GitLab CI Example:**
```yaml
trust_store_update:
  script:
    - ./go-trust-store-manager/bin/trust-store-manager-linux-amd64 
        --auto -d $CI_PROJECT_DIR -c $NEW_CERTIFICATE --webhook 
        --webhook-url $AUDIT_ENDPOINT --webhook-key $AUDIT_API_KEY
```

### Enterprise Scenarios

**Multi-Environment Baseline Sync:**
```bash
# Sync all environments with corporate baseline
for env in dev staging prod; do
  ./bin/trust-store-manager-linux-amd64 \
    --auto \
    -d "/apps/$env" \
    -b "https://pki.company.com/baseline-$env.pem" \
    --webhook --webhook-url "https://audit.company.com/trust-stores" \
    --verbose
done
```

**Compliance Reporting:**
```bash
# Generate compliance report without changes
./bin/trust-store-manager-linux-amd64 \
  --compare-only \
  -b https://compliance.company.com/required-certs.pem \
  -d /production \
  --webhook --webhook-url https://compliance.company.com/reports \
  --verbose
```

## 🔧 Building from Source

### Prerequisites
- **Go 1.20+** (latest version recommended)
- **OpenSSL** (for certificate operations)
- **Java keytool** (for JKS operations, optional)

### Build Commands

**Build for Current Platform:**
```bash
go build -o trust-store-manager
```

**Build for All Platforms:**
```bash
./build.sh
# Creates binaries in ./build/ directory
```

**Using Makefile:**
```bash
make build        # Current platform
make build-all     # All platforms  
make test          # Run tests
make clean         # Clean build artifacts
```

### Custom Build Options

```bash
# Build with custom flags
go build -ldflags="-s -w -X main.version=1.2.3" -o trust-store-manager

# Build statically linked binary
CGO_ENABLED=0 go build -a -ldflags="-s -w" -o trust-store-manager
```

## 🧪 Testing & Validation

### Built-in Test Environment
```bash
# Test with provided keystores
./bin/trust-store-manager-darwin-arm64 --auto -d ./test_keystores/ --verbose

# Interactive demo for learning
./scripts/interactive_demo.sh
```

### Integration Testing
```bash
# Test webhook functionality
./bin/trust-store-manager-darwin-arm64 \
  --webhook --webhook-url http://localhost:3000/test \
  --auto -d ./test_keystores/ \
  --verbose
```

## 🔍 Troubleshooting

### Common Issues

**Binary Won't Execute:**
```bash
# Make binary executable
chmod +x ./bin/trust-store-manager-*

# Check platform compatibility
file ./bin/trust-store-manager-darwin-arm64
uname -m  # Compare with binary architecture
```

**Interactive Mode Issues:**
```bash
# Force auto mode if interactive fails
./bin/trust-store-manager-linux-amd64 --auto --help

# Check terminal compatibility
echo $TERM
```

**Webhook Connection Failures:**
```bash
# Test webhook endpoint
curl -X POST -H "Content-Type: application/json" \
  -d '{"test": "data"}' \
  https://your-webhook-url.com/endpoint

# Enable debug mode
./bin/trust-store-manager-linux-amd64 --auto --verbose -d ./test
```

### Debug Mode
```bash
# Maximum verbosity with debug information
./bin/trust-store-manager-linux-amd64 \
  --auto --verbose \
  -d /path/to/debug \
  --log debug.log \
  -c /path/to/cert.pem
```

## 🔐 Security Features

- **No Network Calls**: Except for explicit baseline URL downloads and webhooks
- **Backup Creation**: Automatic backups before any trust store modifications
- **Dry-Run Mode**: Full preview capability with `--noop` flag
- **Audit Logging**: Comprehensive logging with optional webhook integration
- **Access Control**: Respects file system permissions and user privileges

## 🚀 Performance Characteristics

- **Fast Startup**: < 100ms initialization time
- **Memory Efficient**: < 50MB memory usage for typical operations
- **Concurrent Processing**: Parallel trust store processing when safe
- **Large Scale**: Tested with 1000+ trust stores in single operation
- **Cross-Platform**: Identical performance across operating systems

## 📋 System Requirements

### Minimum Requirements
- **No dependencies** (statically compiled binaries)
- **64-bit operating system** (Linux, macOS, Windows)
- **OpenSSL** (for certificate operations, typically pre-installed)

### Optional Requirements
- **Java Runtime** (for JKS trust store operations)
- **Docker** (for Docker mode functionality)
- **kubectl** (for Kubernetes mode functionality)

### Supported Platforms
- ✅ **Linux x64/ARM64** (Ubuntu, CentOS, RHEL, Alpine, etc.)
- ✅ **macOS x64/ARM64** (10.15+, including Apple Silicon)
- ✅ **Windows x64** (Windows 10+, Server 2019+)

## 🗺️ Roadmap

See [ROADMAP.md](./ROADMAP.md) for detailed future plans including:
- Certificate lifecycle management
- Enhanced enterprise integrations  
- Advanced security features
- Performance optimizations

## 🤝 Contributing

1. **Fork the repository** and create a feature branch
2. **Write tests** for new functionality
3. **Run the full test suite**: `make test`
4. **Build for all platforms**: `make build-all`
5. **Update documentation** as needed
6. **Submit a pull request** with clear description

## 📝 License

MIT License - See [LICENSE](./LICENSE) for details.

## 📞 Support & Resources

- **📖 Tutorial**: [TUTORIAL.md](./TUTORIAL.md) - Step-by-step usage guide
- **🗺️ Roadmap**: [ROADMAP.md](./ROADMAP.md) - Future development plans
- **📋 Releases**: [RELEASE_NOTES.md](./RELEASE_NOTES.md) - Version history
- **🧪 Examples**: [examples/](./examples/) - Integration examples
- **🔧 Scripts**: [scripts/](./scripts/) - Helper tools and demos 