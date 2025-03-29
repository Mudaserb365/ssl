# Trust Store Manager

A cross-platform command-line tool written in Go for automating the discovery and modification of trust-store files in various runtimes, containers, and web servers.

## Features

- Automatically finds trust stores in a directory structure
- Supports multiple trust store formats:
  - Java KeyStores (JKS)
  - PKCS12 stores
  - PEM certificate bundles
- Extracts trust store paths from configuration files:
  - Java properties
  - Environment files
  - Node.js configurations
  - Web server configs (Nginx, Apache)
- Compares trust stores against a baseline
- Creates backups before modifying trust stores
- Cross-platform support (Windows, Linux, macOS)
- Remote logging via webhooks for centralized monitoring

## Installation

### Pre-built Binaries

Download the appropriate binary for your platform from the releases page.

### Building from Source

To build from source, you need Go 1.16 or higher installed.

```bash
# Clone the repository
git clone https://github.com/user/trust-store-manager.git
cd trust-store-manager

# Build for your current platform
go build -o trust-store-manager

# Build for all supported platforms
./build.sh
```

## Usage

```bash
./trust-store-manager [options]
```

### Options

```
  -d, --directory DIR       Target directory to scan (default: current directory)
  -c, --certificate FILE    Path to certificate to append (default: auto-generated)
  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)
  -p, --passwords "p1 p2"   Space-separated list of passwords to try (in quotes)
  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)
  -D, --docker              Enable Docker mode (scan common Docker trust store locations)
  -r, --restart             Restart affected services after modification
  -n, --no-backup           Disable backup creation before modification
  -v, --verbose             Enable verbose output
  -b, --baseline URL        URL to download baseline trust store for comparison
  -C, --compare-only        Only compare trust stores, don't modify them
  -h, --help                Display this help message
  
  # Webhook logging options
  --webhook                 Enable webhook logging
  --webhook-url URL         URL to send logs to (e.g., https://example.com/logs)
  --webhook-key KEY         API key for the webhook
```

### Examples

```bash
# Scan current directory and append auto-generated certificate
./trust-store-manager

# Scan specific directory and append specific certificate
./trust-store-manager -d /path/to/project -c /path/to/cert.pem

# Use specific passwords for JKS trust stores
./trust-store-manager -p "changeit password secret"

# Compare trust stores with baseline without modifying them
./trust-store-manager -b https://example.com/baseline.pem -C

# Enable verbose output
./trust-store-manager -v

# Send logs to a webhook for centralized monitoring
./trust-store-manager --webhook --webhook-url https://logs.example.com/api/logs --webhook-key your-api-key
```

## Remote Logging

The Trust Store Manager supports sending logs to a remote webhook endpoint for centralized monitoring and auditing. This is particularly useful when running the tool across multiple servers or in distributed environments.

### Webhook Features

- **Real-time Monitoring**: All significant operations are logged as they happen
- **Host Information Collection**: Automatically gathers system details with each log
- **Authentication Support**: Secure your endpoints with API key authentication
- **Standardized JSON Format**: Consistent log structure for easy parsing
- **Multiple Log Levels**: INFO, SUCCESS, WARNING, ERROR levels for different scenarios
- **Metadata Support**: Additional context data for complex operations

### Webhook JSON Format

When webhook logging is enabled, the tool sends JSON-formatted log entries to the specified endpoint:

```json
{
  "timestamp": "2023-03-29T15:30:45Z",
  "level": "INFO",
  "message": "Processing JKS trust store: /path/to/truststore.jks",
  "host": {
    "hostname": "server-name",
    "ip_addresses": ["192.168.1.100", "10.0.0.5"],
    "os": "linux",
    "os_version": "20.04",
    "arch": "amd64"
  },
  "metadata": {}
}
```

#### Example Log Entries

**Successful Operation**:
```json
{
  "timestamp": "2023-03-29T15:31:20Z",
  "level": "SUCCESS",
  "message": "Successfully imported certificate to /path/to/truststore.jks with alias trust-store-scanner-1648546280",
  "host": {
    "hostname": "app-server-01",
    "ip_addresses": ["192.168.1.100", "10.0.0.5"],
    "os": "linux",
    "os_version": "20.04",
    "arch": "amd64"
  },
  "metadata": {
    "certificate_count": 75,
    "operation": "import",
    "file_type": "JKS"
  }
}
```

**Error Condition**:
```json
{
  "timestamp": "2023-03-29T15:32:10Z",
  "level": "ERROR",
  "message": "Failed to import certificate to /path/to/truststore.jks: keystore password was incorrect",
  "host": {
    "hostname": "app-server-02",
    "ip_addresses": ["192.168.1.101"],
    "os": "windows",
    "os_version": "10.0.19042",
    "arch": "amd64"
  },
  "metadata": {
    "attempted_passwords": 3,
    "file_type": "JKS"
  }
}
```

**Warning Message**:
```json
{
  "timestamp": "2023-03-29T15:33:45Z",
  "level": "WARNING",
  "message": "Certificate already exists in /path/to/cert-bundle.pem",
  "host": {
    "hostname": "web-server-05",
    "ip_addresses": ["10.0.1.25"],
    "os": "darwin",
    "os_version": "12.3.1",
    "arch": "arm64"
  },
  "metadata": {
    "certificate_fingerprint": "A1:B2:C3:D4:E5:F6:...",
    "file_type": "PEM"
  }
}
```

### Setting Up Webhook Logging

To enable webhook logging, use the following command-line flags:

```bash
./trust-store-manager --webhook --webhook-url https://your-logging-server.com/api/logs
```

If your webhook endpoint requires authentication:

```bash
./trust-store-manager --webhook --webhook-url https://your-logging-server.com/api/logs --webhook-key your-api-key
```

The API key will be appended to the URL as a query parameter: `?apikey=your-api-key`

### Integration Examples

#### ELK Stack Integration

For Elasticsearch, Logstash, and Kibana integration:

```bash
./trust-store-manager --webhook --webhook-url http://logstash-server:8080/json
```

With a corresponding Logstash configuration:

```
input {
  http {
    port => 8080
    response_code => 200
  }
}
filter {
  json {
    source => "message"
  }
}
output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "trust-store-manager-%{+YYYY.MM.dd}"
  }
}
```

#### Custom Webhook Server

A simple Node.js webhook receiver example:

```javascript
const express = require('express');
const app = express();
app.use(express.json());

app.post('/logs', (req, res) => {
  console.log(JSON.stringify(req.body, null, 2));
  // Save to database, forward to monitoring system, etc.
  res.sendStatus(200);
});

app.listen(3000, () => {
  console.log('Webhook receiver listening on port 3000');
});
```

Run the trust store manager with:

```bash
./trust-store-manager --webhook --webhook-url http://localhost:3000/logs
```

## Dependencies

The tool has minimal dependencies:

- Go standard library
- Operating system tools:
  - `openssl` - Required for handling certificates
  - `keytool` - Required for handling Java KeyStores (JKS)

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. 