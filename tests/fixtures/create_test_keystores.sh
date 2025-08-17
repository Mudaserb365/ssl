#!/bin/bash

# Create Test Keystores and Trust Stores for All Formats
# This script generates test certificates and trust stores for comprehensive testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Creating comprehensive test trust stores and certificates...${NC}"

# Create directories
mkdir -p "$FIXTURES_DIR"/{jks,pkcs12,pem,certificates}

# Function to check if keytool is available
check_keytool() {
    if ! command -v keytool >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: keytool not found. JKS and PKCS12 tests will be limited.${NC}"
        echo "Please install Java JDK/JRE or set JAVA_HOME environment variable."
        return 1
    fi
    return 0
}

# Function to create a test certificate
create_test_certificate() {
    local name="$1"
    local subject="$2"
    
    echo "Creating test certificate: $name"
    
    # Create private key
    openssl genrsa -out "$FIXTURES_DIR/certificates/${name}.key" 2048
    
    # Create certificate signing request
    openssl req -new -key "$FIXTURES_DIR/certificates/${name}.key" \
        -out "$FIXTURES_DIR/certificates/${name}.csr" \
        -subj "$subject"
    
    # Create self-signed certificate
    openssl x509 -req -in "$FIXTURES_DIR/certificates/${name}.csr" \
        -signkey "$FIXTURES_DIR/certificates/${name}.key" \
        -out "$FIXTURES_DIR/certificates/${name}.crt" \
        -days 365
    
    # Create PEM format (certificate + key)
    cat "$FIXTURES_DIR/certificates/${name}.crt" "$FIXTURES_DIR/certificates/${name}.key" \
        > "$FIXTURES_DIR/certificates/${name}.pem"
}

# Function to create CA certificate
create_ca_certificate() {
    echo "Creating test CA certificate"
    
    # Create CA private key
    openssl genrsa -out "$FIXTURES_DIR/certificates/test-ca.key" 4096
    
    # Create CA certificate
    openssl req -new -x509 -key "$FIXTURES_DIR/certificates/test-ca.key" \
        -out "$FIXTURES_DIR/certificates/test-ca.crt" \
        -days 365 \
        -subj "/C=US/ST=Test/L=Test/O=Test CA/OU=Testing/CN=Test Root CA"
    
    # Create PEM format
    cp "$FIXTURES_DIR/certificates/test-ca.crt" "$FIXTURES_DIR/certificates/test-ca.pem"
}

# Function to create PEM trust stores
create_pem_trust_stores() {
    echo "Creating PEM trust stores"
    
    # Basic trust store with single certificate
    cp "$FIXTURES_DIR/certificates/test-ca.crt" "$FIXTURES_DIR/pem/basic-trust-store.pem"
    
    # Multi-certificate trust store
    cat "$FIXTURES_DIR/certificates/test-ca.crt" \
        "$FIXTURES_DIR/certificates/server.crt" \
        "$FIXTURES_DIR/certificates/client.crt" \
        > "$FIXTURES_DIR/pem/multi-cert-trust-store.pem"
    
    # Empty trust store
    touch "$FIXTURES_DIR/pem/empty-trust-store.pem"
    
    # Invalid trust store (corrupted)
    echo "INVALID CERTIFICATE DATA" > "$FIXTURES_DIR/pem/invalid-trust-store.pem"
    
    # Large trust store (for performance testing)
    cp "$FIXTURES_DIR/certificates/test-ca.crt" "$FIXTURES_DIR/pem/large-trust-store.pem"
    for i in {1..10}; do
        cat "$FIXTURES_DIR/certificates/server.crt" >> "$FIXTURES_DIR/pem/large-trust-store.pem"
    done
}

# Function to create JKS trust stores
create_jks_trust_stores() {
    if ! check_keytool; then
        echo "Skipping JKS trust store creation - keytool not available"
        return
    fi
    
    echo "Creating JKS trust stores"
    
    # Basic JKS trust store with default password
    keytool -import -trustcacerts -noprompt \
        -alias testca \
        -file "$FIXTURES_DIR/certificates/test-ca.crt" \
        -keystore "$FIXTURES_DIR/jks/basic-truststore.jks" \
        -storepass changeit
    
    # JKS trust store with custom password
    keytool -import -trustcacerts -noprompt \
        -alias testca \
        -file "$FIXTURES_DIR/certificates/test-ca.crt" \
        -keystore "$FIXTURES_DIR/jks/custom-password-truststore.jks" \
        -storepass secretpass
    
    # Multi-certificate JKS trust store
    keytool -import -trustcacerts -noprompt \
        -alias testca \
        -file "$FIXTURES_DIR/certificates/test-ca.crt" \
        -keystore "$FIXTURES_DIR/jks/multi-cert-truststore.jks" \
        -storepass changeit
    
    keytool -import -trustcacerts -noprompt \
        -alias server \
        -file "$FIXTURES_DIR/certificates/server.crt" \
        -keystore "$FIXTURES_DIR/jks/multi-cert-truststore.jks" \
        -storepass changeit
    
    keytool -import -trustcacerts -noprompt \
        -alias client \
        -file "$FIXTURES_DIR/certificates/client.crt" \
        -keystore "$FIXTURES_DIR/jks/multi-cert-truststore.jks" \
        -storepass changeit
    
    # Empty JKS trust store
    keytool -genkeypair -noprompt \
        -alias temp \
        -keyalg RSA \
        -keysize 2048 \
        -validity 1 \
        -dname "CN=temp" \
        -keystore "$FIXTURES_DIR/jks/empty-truststore.jks" \
        -storepass changeit \
        -keypass changeit
    
    keytool -delete -noprompt \
        -alias temp \
        -keystore "$FIXTURES_DIR/jks/empty-truststore.jks" \
        -storepass changeit
    
    # Create corrupted JKS (invalid file)
    echo "INVALID JKS DATA" > "$FIXTURES_DIR/jks/corrupted-truststore.jks"
    
    # JKS with various password combinations for testing
    local passwords=("changeit" "changeme" "password" "keystore" "truststore" "secret" "")
    for i in "${!passwords[@]}"; do
        local pass="${passwords[$i]}"
        local filename="password-test-$i.jks"
        
        if [[ -z "$pass" ]]; then
            # Empty password
            keytool -import -trustcacerts -noprompt \
                -alias testca \
                -file "$FIXTURES_DIR/certificates/test-ca.crt" \
                -keystore "$FIXTURES_DIR/jks/$filename" \
                -storepass ""
        else
            keytool -import -trustcacerts -noprompt \
                -alias testca \
                -file "$FIXTURES_DIR/certificates/test-ca.crt" \
                -keystore "$FIXTURES_DIR/jks/$filename" \
                -storepass "$pass"
        fi
    done
}

# Function to create PKCS12 trust stores
create_pkcs12_trust_stores() {
    if ! check_keytool; then
        echo "Skipping PKCS12 trust store creation - keytool not available"
        return
    fi
    
    echo "Creating PKCS12 trust stores"
    
    # Basic PKCS12 trust store
    keytool -import -trustcacerts -noprompt \
        -alias testca \
        -file "$FIXTURES_DIR/certificates/test-ca.crt" \
        -keystore "$FIXTURES_DIR/pkcs12/basic-truststore.p12" \
        -storetype PKCS12 \
        -storepass changeit
    
    # PKCS12 with custom password
    keytool -import -trustcacerts -noprompt \
        -alias testca \
        -file "$FIXTURES_DIR/certificates/test-ca.crt" \
        -keystore "$FIXTURES_DIR/pkcs12/custom-password-truststore.p12" \
        -storetype PKCS12 \
        -storepass secretpass
    
    # Multi-certificate PKCS12
    keytool -import -trustcacerts -noprompt \
        -alias testca \
        -file "$FIXTURES_DIR/certificates/test-ca.crt" \
        -keystore "$FIXTURES_DIR/pkcs12/multi-cert-truststore.p12" \
        -storetype PKCS12 \
        -storepass changeit
    
    keytool -import -trustcacerts -noprompt \
        -alias server \
        -file "$FIXTURES_DIR/certificates/server.crt" \
        -keystore "$FIXTURES_DIR/pkcs12/multi-cert-truststore.p12" \
        -storetype PKCS12 \
        -storepass changeit
    
    # PKCS12 with .pfx extension
    cp "$FIXTURES_DIR/pkcs12/basic-truststore.p12" "$FIXTURES_DIR/pkcs12/basic-truststore.pfx"
    
    # Create corrupted PKCS12
    echo "INVALID PKCS12 DATA" > "$FIXTURES_DIR/pkcs12/corrupted-truststore.p12"
}

# Function to create test metadata
create_test_metadata() {
    echo "Creating test metadata"
    
    cat > "$FIXTURES_DIR/test-metadata.json" << 'EOF'
{
  "description": "Test fixtures for Trust Store Manager",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "fixtures": {
    "certificates": {
      "test-ca.crt": {
        "type": "CA Certificate",
        "subject": "CN=Test Root CA",
        "format": "PEM"
      },
      "server.crt": {
        "type": "Server Certificate", 
        "subject": "CN=test-server.example.com",
        "format": "PEM"
      },
      "client.crt": {
        "type": "Client Certificate",
        "subject": "CN=test-client.example.com", 
        "format": "PEM"
      }
    },
    "jks_trust_stores": {
      "basic-truststore.jks": {
        "password": "changeit",
        "certificates": 1,
        "description": "Basic JKS trust store"
      },
      "custom-password-truststore.jks": {
        "password": "secretpass",
        "certificates": 1,
        "description": "JKS with custom password"
      },
      "multi-cert-truststore.jks": {
        "password": "changeit", 
        "certificates": 3,
        "description": "JKS with multiple certificates"
      },
      "empty-truststore.jks": {
        "password": "changeit",
        "certificates": 0,
        "description": "Empty JKS trust store"
      }
    },
    "pkcs12_trust_stores": {
      "basic-truststore.p12": {
        "password": "changeit",
        "certificates": 1,
        "description": "Basic PKCS12 trust store"
      },
      "custom-password-truststore.p12": {
        "password": "secretpass", 
        "certificates": 1,
        "description": "PKCS12 with custom password"
      },
      "multi-cert-truststore.p12": {
        "password": "changeit",
        "certificates": 2,
        "description": "PKCS12 with multiple certificates"
      }
    },
    "pem_trust_stores": {
      "basic-trust-store.pem": {
        "certificates": 1,
        "description": "Basic PEM trust store"
      },
      "multi-cert-trust-store.pem": {
        "certificates": 3,
        "description": "PEM with multiple certificates"
      },
      "empty-trust-store.pem": {
        "certificates": 0,
        "description": "Empty PEM trust store"
      },
      "large-trust-store.pem": {
        "certificates": 11,
        "description": "Large PEM trust store for performance testing"
      }
    }
  }
}
EOF
}

# Main execution
main() {
    echo -e "${GREEN}Starting test fixture creation...${NC}"
    
    # Check if OpenSSL is available
    if ! command -v openssl >/dev/null 2>&1; then
        echo "Error: OpenSSL is required but not found. Please install OpenSSL."
        exit 1
    fi
    
    # Create test certificates
    create_ca_certificate
    create_test_certificate "server" "/C=US/ST=Test/L=Test/O=Test Server/OU=Testing/CN=test-server.example.com"
    create_test_certificate "client" "/C=US/ST=Test/L=Test/O=Test Client/OU=Testing/CN=test-client.example.com"
    create_test_certificate "expired" "/C=US/ST=Test/L=Test/O=Test Expired/OU=Testing/CN=expired.example.com"
    
    # Create trust stores in all formats
    create_pem_trust_stores
    create_jks_trust_stores
    create_pkcs12_trust_stores
    
    # Create test metadata
    create_test_metadata
    
    echo -e "${GREEN}Test fixture creation completed!${NC}"
    echo -e "${YELLOW}Generated files:${NC}"
    find "$FIXTURES_DIR" -type f -name "*" | sort
    
    echo
    echo -e "${GREEN}Usage in tests:${NC}"
    echo "- JKS files: tests/fixtures/jks/"
    echo "- PKCS12 files: tests/fixtures/pkcs12/"
    echo "- PEM files: tests/fixtures/pem/"
    echo "- Certificates: tests/fixtures/certificates/"
    echo "- Test metadata: tests/fixtures/test-metadata.json"
}

# Execute main function
main "$@" 