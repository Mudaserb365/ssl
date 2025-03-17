# SSL Test Website

A containerized web application that displays SSL certificate properties of the deployed server certificate. This application is designed to run on an EC2 instance and provides a clean, user-friendly interface for viewing certificate details.

## Directory Structure

```
ssl_test_website/
├── Dockerfile              # Container configuration
├── docker-compose.yml     # Docker Compose configuration
├── requirements.txt       # Python dependencies
├── entrypoint.sh         # Container entrypoint script
├── src/                  # Website source files
│   ├── index.html       # Main HTML page
│   ├── styles.css       # CSS styles
│   ├── script.js        # Frontend JavaScript
│   └── app.py          # Python Flask backend
├── nginx/               # Nginx configuration
│   ├── nginx.conf      # Main Nginx config
│   └── default.conf    # Site-specific config
└── certs/              # SSL certificates (mount point)
    ├── server.crt      # Server certificate
    └── server.key      # Private key
```

## Components

### 1. Frontend (src/)
- **index.html**: Bootstrap-based responsive layout
- **styles.css**: Custom styling for certificate properties
- **script.js**: Handles API calls and dynamic content updates

### 2. Backend (src/app.py)
- Flask application that reads and parses certificate information
- Provides REST API endpoint for certificate details
- Extracts comprehensive certificate information:
  - Subject
  - Issuer
  - Version
  - Serial Number
  - Validity Period
  - Signature Algorithm
  - SSL/TLS Protocol Version

### 3. Nginx Configuration (nginx/)
- **nginx.conf**: Main server configuration
- **default.conf**: Site-specific settings
  - HTTP to HTTPS redirect
  - SSL configuration
  - Static file serving
  - API proxy settings

### 4. Docker Configuration
- **Dockerfile**: Multi-stage build with Nginx and Python
- **docker-compose.yml**: Container orchestration
  - Port mappings (80, 443)
  - Certificate volume mounting
  - Automatic restart policy

## Security Features

1. **SSL/TLS Configuration**
   - TLS 1.2 and 1.3 only
   - Strong cipher suite selection
   - Automatic HTTP to HTTPS redirect

2. **Certificate Handling**
   - Certificates mounted from host system
   - Private key protection
   - Real-time certificate information display

## Prerequisites

1. EC2 Instance Requirements:
   - Amazon Linux 2 or compatible Linux distribution
   - Minimum t2.micro instance type
   - Security group with ports 80 and 443 open

2. Software Requirements:
   - Docker
   - Docker Compose
   - Git (optional)

## Installation

1. Install Docker and Docker Compose:
   ```bash
   # Update system
   sudo yum update -y

   # Install Docker
   sudo yum install docker -y
   sudo service docker start
   sudo usermod -a -G docker ec2-user

   # Install Docker Compose
   sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   ```

2. Clone or copy the repository:
   ```bash
   git clone <repository-url>
   cd ssl_test_website
   ```

3. Add your SSL certificates:
   ```bash
   # Place your certificates in the certs directory
   cp path/to/your/certificate.crt certs/server.crt
   cp path/to/your/private.key certs/server.key
   ```

4. Deploy the application:
   ```bash
   docker-compose up -d
   ```

## Usage

1. Access the website:
   ```
   https://your-ec2-domain
   ```

2. View certificate information:
   - The website automatically displays the current server certificate properties
   - Information is updated in real-time
   - All certificate details are presented in a clean, organized format

## Troubleshooting

1. Certificate Issues:
   ```bash
   # Check certificate permissions
   ls -l certs/
   
   # Verify certificate format
   openssl x509 -in certs/server.crt -text -noout
   ```

2. Container Issues:
   ```bash
   # View container logs
   docker-compose logs

   # Restart containers
   docker-compose restart
   ```

3. Common Problems:
   - Certificate permission denied: Ensure proper file permissions
   - Connection refused: Check security group settings
   - 502 Bad Gateway: Verify Flask application is running

## Maintenance

1. Updating Certificates:
   ```bash
   # Replace certificates
   cp new_cert.crt certs/server.crt
   cp new_key.key certs/server.key
   
   # Restart container
   docker-compose restart
   ```

2. Updating Application:
   ```bash
   # Pull latest changes
   git pull
   
   # Rebuild and restart containers
   docker-compose up -d --build
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details. 