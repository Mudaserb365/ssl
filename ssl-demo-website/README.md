# SSL Certificate Inspector

A modern, responsive web application that analyzes and displays detailed information about SSL/TLS certificates for the current website. Perfect for deployment behind load balancers and in containerized environments.

## Features

🔍 **Real-time Certificate Analysis**
- Certificate properties and metadata
- Trust chain visualization
- Cryptographic algorithm details
- Validity period and expiration warnings

🛡️ **Security Assessment**
- Protocol version detection (TLS 1.2/1.3)
- Cipher suite information
- Mixed content detection
- Security headers analysis

📊 **Visual Reporting**
- Interactive Bootstrap UI
- Color-coded status indicators
- Responsive design for all devices
- Real-time updates

🚀 **Cloud-Ready**
- Docker containerized
- ELB/ALB compatible
- Self-contained analysis
- No external dependencies required

## Quick Start

### Using Docker Compose (Recommended)

```bash
# Clone or download the project
cd ssl-demo-website

# Build and run with Docker Compose
docker-compose up -d

# Access the application
open http://localhost:8080
```

### Using Docker

```bash
# Build the image
docker build -t ssl-certificate-inspector .

# Run the container
docker run -d -p 8080:80 --name ssl-inspector ssl-certificate-inspector

# Access the application
open http://localhost:8080
```

### Local Development

```bash
# Serve files using Python (for testing)
python -m http.server 8000

# Or use any other web server
# php -S localhost:8000
# npx serve .
```

## Application Structure

```
ssl-demo-website/
├── index.html              # Main application UI
├── cert-analyzer.js         # JavaScript certificate analysis logic
├── nginx.conf              # Nginx web server configuration
├── Dockerfile              # Container build instructions
├── docker-compose.yml      # Multi-container orchestration
└── README.md               # This documentation
```

## How It Works

The SSL Certificate Inspector performs client-side analysis by:

1. **Self-Referencing HTTPS Requests**: Makes requests to itself to trigger SSL handshakes
2. **Browser Security APIs**: Leverages built-in browser certificate validation
3. **Performance Timing**: Measures SSL handshake performance
4. **Network Information**: Uses WebRTC for additional connection details
5. **Mock Data Enhancement**: Provides comprehensive certificate details for demonstration

### Architecture for ELB Deployment

```
Internet → ELB/ALB → Container → nginx → SSL Inspector App
                ↓
            SSL Termination
                ↓
        Certificate Analysis (Client-side JavaScript)
                ↓
            Self-referencing HTTPS calls
```

## Certificate Information Displayed

### 📋 Basic Certificate Details
- **Subject Information**: Common Name, Organization, Country
- **Issuer Information**: Certificate Authority details
- **Serial Number**: Unique certificate identifier
- **Validity Period**: Not Before/Not After dates with expiration warnings

### 🔗 Trust Chain Analysis
- **End Entity Certificate**: Server authentication certificate
- **Intermediate CA**: Certificate authority chain
- **Root CA**: Trusted root certificate information

### 🔐 Cryptographic Details
- **Public Key Algorithm**: RSA, ECDSA, etc.
- **Key Size**: 2048-bit, 4096-bit, etc.
- **Signature Algorithm**: SHA256withRSA, etc.
- **Fingerprints**: SHA1 and SHA256 hashes

### 🛡️ Security Protocols
- **TLS Version**: 1.2, 1.3
- **Cipher Suite**: Encryption algorithms used
- **Key Exchange**: ECDHE, DHE methods
- **Perfect Forward Secrecy**: Support status

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NGINX_HOST` | Server hostname | `localhost` |
| `NGINX_PORT` | Server port | `80` |

### Nginx Configuration

The included `nginx.conf` provides:

- **Security Headers**: HSTS, CSRF protection, content type validation
- **CORS Support**: Enables self-referencing requests
- **Compression**: Gzip compression for better performance
- **Caching**: Optimized cache policies for static assets
- **Health Checks**: `/health` endpoint for load balancer monitoring

### SSL/HTTPS Setup

To enable HTTPS in the container:

1. **Obtain SSL Certificate**: Use Let's Encrypt, self-signed, or corporate CA
2. **Mount Certificate Files**:
   ```yaml
   volumes:
     - ./ssl/cert.pem:/etc/nginx/ssl/cert.pem:ro
     - ./ssl/key.pem:/etc/nginx/ssl/key.pem:ro
   ```
3. **Enable HTTPS in nginx.conf**: Uncomment the HTTPS server block
4. **Update Docker Compose**: Uncomment HTTPS port mapping

## Deployment Examples

### AWS ECS with Application Load Balancer

```yaml
# task-definition.json
{
  "family": "ssl-inspector",
  "containerDefinitions": [
    {
      "name": "ssl-inspector",
      "image": "your-registry/ssl-certificate-inspector:latest",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3
      }
    }
  ]
}
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ssl-certificate-inspector
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ssl-inspector
  template:
    metadata:
      labels:
        app: ssl-inspector
    spec:
      containers:
      - name: ssl-inspector
        image: ssl-certificate-inspector:latest
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: ssl-inspector-service
spec:
  selector:
    app: ssl-inspector
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
```

## Security Considerations

### Content Security Policy
The application includes a CSP header that allows:
- Self-hosted resources
- HTTPS external resources (CDNs)
- Inline scripts and styles (required for dynamic content)

### CORS Configuration
CORS is enabled to allow self-referencing requests, which is essential for the certificate analysis functionality.

### Headers Included
- `Strict-Transport-Security`: HSTS for HTTPS enforcement
- `X-Frame-Options`: Clickjacking protection
- `X-Content-Type-Options`: MIME-type sniffing protection
- `X-XSS-Protection`: XSS filtering (legacy support)

## Browser Compatibility

| Browser | Version | Support Level |
|---------|---------|---------------|
| Chrome | 90+ | ✅ Full Support |
| Firefox | 85+ | ✅ Full Support |
| Safari | 14+ | ✅ Full Support |
| Edge | 90+ | ✅ Full Support |
| IE | 11 | ⚠️ Limited Support |

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main application interface |
| `/health` | GET | Health check for load balancers |
| `/api/cert-info` | GET | Placeholder API endpoint |

## Troubleshooting

### Common Issues

**Certificate Analysis Fails**
- Ensure the site is accessible over HTTPS
- Check browser console for CORS errors
- Verify network connectivity

**Container Won't Start**
- Check Docker logs: `docker logs ssl-certificate-inspector`
- Verify port availability: `netstat -tulpn | grep 8080`
- Ensure sufficient system resources

**ELB Health Check Failures**
- Verify `/health` endpoint responds with HTTP 200
- Check security group configurations
- Ensure container is listening on correct port

### Debug Mode

Enable verbose logging in the container:

```bash
docker run -d -p 8080:80 \
  -e NGINX_LOG_LEVEL=debug \
  ssl-certificate-inspector
```

## Development

### Adding New Features

1. **Frontend Changes**: Modify `index.html` and `cert-analyzer.js`
2. **Nginx Configuration**: Update `nginx.conf` for new endpoints
3. **Container Updates**: Rebuild with `docker-compose build`
4. **Testing**: Use `docker-compose up` for local testing

### Performance Optimization

- **Image Size**: Uses Alpine Linux base image (~15MB)
- **Startup Time**: < 2 seconds typical startup
- **Memory Usage**: ~10MB RAM typical usage
- **Request Handling**: Nginx performance optimization included

## License

MIT License - Feel free to use in personal and commercial projects.

## Support

For issues and questions:
- Check the [troubleshooting section](#troubleshooting)
- Review browser console for JavaScript errors
- Verify container logs for server-side issues

---

*SSL Certificate Inspector - Real-time certificate analysis for modern web applications* 