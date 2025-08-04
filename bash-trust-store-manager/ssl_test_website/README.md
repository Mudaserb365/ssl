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
    ├── server.key      # Private key
    ├── chain.crt       # Certificate chain file (intermediate + root)
    ├── intermediate-ca.crt # Intermediate CA certificate
    └── root-ca.crt     # Root CA certificate
```

## Components

### 1. Frontend (src/)
- **index.html**: Clean, responsive layout with terminal-like display
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
  - Certificate Extensions
  - Certificate Chain Information

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
   - Complete certificate trust chain display

## Prerequisites

1. EC2 Instance Requirements:
   - Amazon Linux 2 or compatible Linux distribution
   - Minimum t2.micro instance type
   - Security group with ports 80 and 443 open

2. Software Requirements:
   - Docker
   - Docker Compose
   - Git (optional)
   - OpenSSL (for certificate management)

## Certificate Trust Chain Setup

### Option 1: Using Existing Certificates

If you have a complete certificate chain from a Certificate Authority:

1. Place your server certificate in `certs/server.crt`
2. Place your private key in `certs/server.key`
3. Create a chain file by concatenating your intermediate and root CA certificates:
   ```bash
   cat intermediate-ca.crt root-ca.crt > certs/chain.crt
   ```
4. Optionally, keep individual certificates for reference:
   ```bash
   cp intermediate-ca.crt certs/intermediate-ca.crt
   cp root-ca.crt certs/root-ca.crt
   ```

### Option 2: Creating a Self-Signed Certificate Chain

For testing purposes, you can create a complete certificate chain:

1. Create a root CA:
   ```bash
   openssl req -x509 -sha256 -days 3650 -nodes -newkey rsa:4096 \
     -subj "/C=US/ST=State/L=City/O=Test Root CA/CN=Test Root CA" \
     -keyout certs/root-ca.key -out certs/root-ca.crt
   ```

2. Create an intermediate CA:
   ```bash
   # Create CSR and key
   openssl req -new -sha256 -nodes -newkey rsa:4096 \
     -subj "/C=US/ST=State/L=City/O=Test Intermediate CA/CN=Test Intermediate CA" \
     -keyout certs/intermediate-ca.key -out certs/intermediate-ca.csr

   # Sign with root CA
   openssl x509 -req -sha256 -days 3650 -in certs/intermediate-ca.csr \
     -CA certs/root-ca.crt -CAkey certs/root-ca.key -CAcreateserial \
     -out certs/intermediate-ca.crt \
     -extfile <(printf "basicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,cRLSign,keyCertSign")
   ```

3. Create a server certificate:
   ```bash
   # Create CSR and key
   openssl req -new -sha256 -nodes -newkey rsa:2048 \
     -subj "/C=US/ST=State/L=City/O=Test Server/CN=localhost" \
     -keyout certs/server.key -out certs/server.csr

   # Sign with intermediate CA
   openssl x509 -req -sha256 -days 365 -in certs/server.csr \
     -CA certs/intermediate-ca.crt -CAkey certs/intermediate-ca.key -CAcreateserial \
     -out certs/server.crt \
     -extfile <(printf "basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost")
   ```

4. Create the chain file:
   ```bash
   cat certs/intermediate-ca.crt certs/root-ca.crt > certs/chain.crt
   ```

5. Verify the certificate chain:
   ```bash
   openssl verify -CAfile certs/root-ca.crt -untrusted certs/intermediate-ca.crt certs/server.crt
   ```

### Option 3: Using Let's Encrypt Certificates

If using Let's Encrypt with certbot:

1. After obtaining certificates, copy them to the certs directory:
   ```bash
   cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem certs/server.crt
   cp /etc/letsencrypt/live/yourdomain.com/privkey.pem certs/server.key
   cp /etc/letsencrypt/live/yourdomain.com/chain.pem certs/chain.crt
   ```

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

3. Set up your SSL certificates as described in the "Certificate Trust Chain Setup" section.

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
   - The complete certificate chain is shown (Server, Intermediate CA, Root CA)
   - Connection information including protocol and cipher suite is displayed
   - All certificate details are presented in a clean, organized format

## Troubleshooting

1. Certificate Issues:
   ```bash
   # Check certificate permissions
   ls -l certs/
   
   # Verify certificate format
   openssl x509 -in certs/server.crt -text -noout
   
   # Verify certificate chain
   openssl verify -CAfile certs/root-ca.crt -untrusted certs/intermediate-ca.crt certs/server.crt
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
   - Missing certificate chain: Ensure chain.crt file is properly created

## Maintenance

1. Updating Certificates:
   ```bash
   # Replace certificates
   cp new_cert.crt certs/server.crt
   cp new_key.key certs/server.key
   cp new_chain.crt certs/chain.crt
   
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