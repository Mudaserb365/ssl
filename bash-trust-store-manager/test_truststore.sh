#!/bin/bash
# Script to validate trust stores with web servers and MTLS connections
# This script is meant to be called by compare_and_update.sh or directly by the user

set -e

# Default values
TARGET_DIR="."
WEB_SERVER_HOST="localhost"
WEB_SERVER_PORT="443"
MTLS_PORT="8443"
CLIENT_CERT=""
CLIENT_KEY=""
VERBOSE=false

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -d, --directory DIR       Target directory to scan (default: current directory)"
    echo "  -h, --host HOSTNAME       Web server hostname/IP (default: localhost)"
    echo "  -p, --port PORT           Web server port (default: 443)"
    echo "  -m, --mtls-port PORT      MTLS port (default: 8443)"
    echo "  -c, --client-cert FILE    Client certificate for MTLS (required for MTLS test)"
    echo "  -k, --client-key FILE     Client key for MTLS (required for MTLS test)"
    echo "  -v, --verbose             Enable verbose output"
    echo "  --help                    Display this help message"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 -d /path/to/project -h example.com"
    echo "  $0 -c /path/to/client.crt -k /path/to/client.key"
    exit 0
}

# Check for help flag first
if [[ "$1" == "--help" ]]; then
    show_help
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--directory)
            TARGET_DIR="$2"
            shift 2
            ;;
        -h|--host)
            WEB_SERVER_HOST="$2"
            shift 2
            ;;
        -p|--port)
            WEB_SERVER_PORT="$2"
            shift 2
            ;;
        -m|--mtls-port)
            MTLS_PORT="$2"
            shift 2
            ;;
        -c|--client-cert)
            CLIENT_CERT="$2"
            shift 2
            ;;
        -k|--client-key)
            CLIENT_KEY="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Function to log verbose messages
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "$1"
    fi
}

# Function to find all trust stores in the given directory
find_trust_stores() {
    local dir="$1"
    local trust_stores=()
    
    # Find PEM trust stores
    log_verbose "Searching for PEM trust stores in $dir"
    while IFS= read -r file; do
        if grep -q "BEGIN CERTIFICATE" "$file" 2>/dev/null; then
            trust_stores+=("$file")
        fi
    done < <(find "$dir" -type f -name "*.pem" -o -name "*.crt" -o -name "*.cert" 2>/dev/null | grep -v "client")
    
    # Find JKS trust stores
    log_verbose "Searching for JKS trust stores in $dir"
    while IFS= read -r file; do
        trust_stores+=("$file")
    done < <(find "$dir" -type f -name "*.jks" -o -name "*.keystore" -o -name "*.truststore" 2>/dev/null)
    
    # Return the found trust stores
    for store in "${trust_stores[@]}"; do
        echo "$store"
    done
}

# Function to test a trust store against a web server
test_web_server() {
    local trust_store="$1"
    local host="$2"
    local port="$3"
    
    echo "Testing trust store $trust_store against web server $host:$port"
    
    # Get extension to determine trust store type
    ext="${trust_store##*.}"
    
    if [[ "$ext" == "jks" || "$ext" == "keystore" || "$ext" == "truststore" ]]; then
        # JKS trust store test
        echo "JKS trust store detected, testing with Java keytool"
        for password in "changeit" "changeme" "password" "keystore" "truststore" "secret"; do
            if java -Djavax.net.ssl.trustStore="$trust_store" \
                    -Djavax.net.ssl.trustStorePassword="$password" \
                    -Djavax.net.ssl.trustStoreType="JKS" \
                    -cp /dev/null \
                    $([ "$VERBOSE" = true ] && echo "-Djavax.net.debug=ssl:handshake:verbose") \
                    TestSSL "$host" "$port" 2>/dev/null; then
                echo "SUCCESS: Successfully verified connection using trust store $trust_store"
                return 0
            fi
        done
        echo "FAILURE: Could not establish SSL connection using trust store $trust_store"
        return 1
    else
        # PEM trust store test with curl or openssl
        if command -v curl >/dev/null 2>&1; then
            if curl --cacert "$trust_store" -s -o /dev/null -w "%{http_code}\n" "https://$host:$port/" | grep -q "200\|301\|302"; then
                echo "SUCCESS: Successfully verified connection using trust store $trust_store"
                return 0
            else
                echo "FAILURE: Could not establish SSL connection using trust store $trust_store"
                return 1
            fi
        elif command -v openssl >/dev/null 2>&1; then
            if echo -n | openssl s_client -connect "$host:$port" -CAfile "$trust_store" -verify_return_error -verify 9 -verify_hostname "$host" 2>/dev/null | grep -q "Verify return code: 0"; then
                echo "SUCCESS: Successfully verified connection using trust store $trust_store"
                return 0
            else
                echo "FAILURE: Could not establish SSL connection using trust store $trust_store"
                return 1
            fi
        else
            echo "ERROR: Neither curl nor openssl is available for testing"
            return 1
        fi
    fi
}

# Function to test a trust store against an MTLS connection
test_mtls() {
    local trust_store="$1"
    local host="$2"
    local port="$3"
    local client_cert="$4"
    local client_key="$5"
    
    echo "Testing trust store $trust_store against MTLS server $host:$port"
    
    # Get extension to determine trust store type
    ext="${trust_store##*.}"
    
    if [[ "$ext" == "jks" || "$ext" == "keystore" || "$ext" == "truststore" ]]; then
        # JKS trust store and client cert test
        echo "JKS trust store detected, testing with Java keytool"
        if [ -z "$client_cert" ] || [ -z "$client_key" ]; then
            echo "ERROR: Client certificate and key required for MTLS test with JKS trust store"
            return 1
        fi
        
        # Convert client cert and key to PKCS12
        tempdir=$(mktemp -d)
        trap 'rm -rf "$tempdir"' EXIT
        
        openssl pkcs12 -export -in "$client_cert" -inkey "$client_key" -out "$tempdir/client.p12" -password pass:changeit
        
        for password in "changeit" "changeme" "password" "keystore" "truststore" "secret"; do
            if java -Djavax.net.ssl.trustStore="$trust_store" \
                    -Djavax.net.ssl.trustStorePassword="$password" \
                    -Djavax.net.ssl.keyStore="$tempdir/client.p12" \
                    -Djavax.net.ssl.keyStorePassword="changeit" \
                    -Djavax.net.ssl.trustStoreType="JKS" \
                    -Djavax.net.ssl.keyStoreType="PKCS12" \
                    -cp /dev/null \
                    $([ "$VERBOSE" = true ] && echo "-Djavax.net.debug=ssl:handshake:verbose") \
                    TestSSL "$host" "$port" 2>/dev/null; then
                echo "SUCCESS: Successfully verified MTLS connection using trust store $trust_store"
                return 0
            fi
        done
        echo "FAILURE: Could not establish MTLS connection using trust store $trust_store"
        return 1
    else
        # PEM trust store test with curl or openssl
        if [ -z "$client_cert" ] || [ -z "$client_key" ]; then
            echo "ERROR: Client certificate and key required for MTLS test"
            return 1
        fi
        
        if command -v curl >/dev/null 2>&1; then
            if curl --cacert "$trust_store" --cert "$client_cert" --key "$client_key" -s -o /dev/null -w "%{http_code}\n" "https://$host:$port/" | grep -q "200\|301\|302"; then
                echo "SUCCESS: Successfully verified MTLS connection using trust store $trust_store"
                return 0
            else
                echo "FAILURE: Could not establish MTLS connection using trust store $trust_store"
                return 1
            fi
        elif command -v openssl >/dev/null 2>&1; then
            if echo -n | openssl s_client -connect "$host:$port" -CAfile "$trust_store" -cert "$client_cert" -key "$client_key" -verify_return_error -verify 9 -verify_hostname "$host" 2>/dev/null | grep -q "Verify return code: 0"; then
                echo "SUCCESS: Successfully verified MTLS connection using trust store $trust_store"
                return 0
            else
                echo "FAILURE: Could not establish MTLS connection using trust store $trust_store"
                return 1
            fi
        else
            echo "ERROR: Neither curl nor openssl is available for testing"
            return 1
        fi
    fi
}

# Main script execution
echo "===== Trust Store Validation Tests ====="
echo "Target Directory: $TARGET_DIR"
echo "Web Server: $WEB_SERVER_HOST:$WEB_SERVER_PORT"
echo "MTLS Server: $WEB_SERVER_HOST:$MTLS_PORT"

# Find all trust stores
trust_stores=($(find_trust_stores "$TARGET_DIR"))
if [ ${#trust_stores[@]} -eq 0 ]; then
    echo "No trust stores found in $TARGET_DIR"
    exit 1
fi

echo "Found ${#trust_stores[@]} trust stores to test."

# Create a Java test class for JKS trust store testing
cat > TestSSL.java << 'EOF'
import javax.net.ssl.*;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.cert.*;

public class TestSSL {
    public static void main(String[] args) {
        if (args.length < 2) {
            System.err.println("Usage: java TestSSL <host> <port>");
            System.exit(1);
        }
        
        String host = args[0];
        int port = Integer.parseInt(args[1]);
        
        try {
            SSLSocketFactory factory = (SSLSocketFactory) SSLSocketFactory.getDefault();
            SSLSocket socket = (SSLSocket) factory.createSocket(host, port);
            
            // Enable all supported protocols and cipher suites
            socket.setEnabledProtocols(socket.getSupportedProtocols());
            socket.setEnabledCipherSuites(socket.getSupportedCipherSuites());
            
            // Set hostname verification
            SNIHostName serverName = new SNIHostName(host);
            List<SNIServerName> serverNames = new ArrayList<>();
            serverNames.add(serverName);
            SSLParameters params = socket.getSSLParameters();
            params.setServerNames(serverNames);
            socket.setSSLParameters(params);
            
            // Start handshake
            socket.startHandshake();
            
            // Print certificate chain info if verbose
            if (System.getProperty("javax.net.debug") != null) {
                SSLSession session = socket.getSession();
                Certificate[] certs = session.getPeerCertificates();
                System.out.println("Certificate chain length: " + certs.length);
                for (int i = 0; i < certs.length; i++) {
                    if (certs[i] instanceof X509Certificate) {
                        X509Certificate cert = (X509Certificate) certs[i];
                        System.out.println("Certificate " + (i + 1) + ":");
                        System.out.println("  Subject: " + cert.getSubjectX500Principal());
                        System.out.println("  Issuer: " + cert.getIssuerX500Principal());
                        System.out.println("  Valid from: " + cert.getNotBefore());
                        System.out.println("  Valid until: " + cert.getNotAfter());
                    }
                }
            }
            
            // Close socket
            socket.close();
            System.exit(0);
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
EOF

# Compile the Java test class if javac is available
if command -v javac >/dev/null 2>&1; then
    javac TestSSL.java 2>/dev/null
fi

# Test each trust store against web server
echo "===== Testing Trust Stores against Web Server ====="
web_server_success=0
for trust_store in "${trust_stores[@]}"; do
    if test_web_server "$trust_store" "$WEB_SERVER_HOST" "$WEB_SERVER_PORT"; then
        web_server_success=$((web_server_success + 1))
    fi
done

# Test each trust store against MTLS server if client cert and key are provided
if [ -n "$CLIENT_CERT" ] && [ -n "$CLIENT_KEY" ]; then
    echo "===== Testing Trust Stores against MTLS Server ====="
    mtls_success=0
    for trust_store in "${trust_stores[@]}"; do
        if test_mtls "$trust_store" "$WEB_SERVER_HOST" "$MTLS_PORT" "$CLIENT_CERT" "$CLIENT_KEY"; then
            mtls_success=$((mtls_success + 1))
        fi
    done
    
    echo "===== MTLS Test Summary ====="
    echo "Total trust stores: ${#trust_stores[@]}"
    echo "Successful MTLS connections: $mtls_success"
    if [ $mtls_success -eq 0 ]; then
        echo "WARNING: No trust stores passed MTLS validation tests"
    elif [ $mtls_success -lt ${#trust_stores[@]} ]; then
        echo "WARNING: Some trust stores failed MTLS validation tests"
    else
        echo "SUCCESS: All trust stores passed MTLS validation tests"
    fi
else
    echo "Skipping MTLS tests: client certificate and key not provided"
fi

# Clean up temporary files
if [ -f "TestSSL.java" ]; then
    rm -f TestSSL.java TestSSL.class
fi

echo "===== Web Server Test Summary ====="
echo "Total trust stores: ${#trust_stores[@]}"
echo "Successful web server connections: $web_server_success"
if [ $web_server_success -eq 0 ]; then
    echo "FAILURE: No trust stores passed web server validation tests"
    exit 1
elif [ $web_server_success -lt ${#trust_stores[@]} ]; then
    echo "WARNING: Some trust stores failed web server validation tests"
    exit 0
else
    echo "SUCCESS: All trust stores passed web server validation tests"
    exit 0
fi 