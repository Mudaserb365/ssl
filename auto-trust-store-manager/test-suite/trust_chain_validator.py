#!/usr/bin/env python3

import os
import sys
import ssl
import json
import time
import socket
import argparse
import requests
import subprocess
import urllib3
from OpenSSL import crypto
from datetime import datetime
from pathlib import Path
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("TrustChainValidator")

class TrustChainValidator:
    def __init__(self, config):
        self.config = config
        self.test_results = {
            "webserver": [],
            "mtls": [],
            "summary": {
                "total_tests": 0,
                "passed": 0,
                "failed": 0,
                "start_time": datetime.now().isoformat(),
                "end_time": None
            }
        }
        
        # Disable warnings for self-signed certificates during testing
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    def discover_trust_stores(self):
        """Find all trust stores that need to be validated"""
        trust_stores = []
        
        # Find all PEM trust stores
        for root, _, files in os.walk(self.config.scan_dir):
            for file in files:
                if file.endswith(('.pem', '.crt', '.cert')):
                    file_path = os.path.join(root, file)
                    # Check if it's a certificate file
                    try:
                        with open(file_path, 'rb') as f:
                            content = f.read()
                            if b'-----BEGIN CERTIFICATE-----' in content:
                                trust_stores.append({
                                    'path': file_path,
                                    'type': 'pem',
                                    'cert_count': content.count(b'-----BEGIN CERTIFICATE-----')
                                })
                    except Exception as e:
                        logger.error(f"Error reading {file_path}: {str(e)}")
        
        # Find all JKS trust stores if keytool is available
        try:
            subprocess.run(['keytool', '-help'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for root, _, files in os.walk(self.config.scan_dir):
                for file in files:
                    if file.endswith(('.jks', '.keystore', '.truststore')):
                        file_path = os.path.join(root, file)
                        # Try with different passwords
                        for password in ["changeit", "password", "truststore"]:
                            try:
                                proc = subprocess.run(
                                    ['keytool', '-list', '-keystore', file_path, '-storepass', password],
                                    stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE,
                                    text=True
                                )
                                if proc.returncode == 0:
                                    # Count certificate entries
                                    cert_count = proc.stdout.count("Certificate fingerprint")
                                    trust_stores.append({
                                        'path': file_path,
                                        'type': 'jks',
                                        'password': password,
                                        'cert_count': cert_count
                                    })
                                    break
                            except Exception as e:
                                logger.error(f"Error with keytool for {file_path}: {str(e)}")
        except FileNotFoundError:
            logger.warning("keytool not found, skipping JKS trust store discovery")
        
        logger.info(f"Discovered {len(trust_stores)} trust stores")
        return trust_stores
    
    def test_webserver_connection(self, trust_store):
        """Test TLS connection to a webserver using the specified trust store"""
        test_case = {
            "trust_store": trust_store['path'],
            "target": self.config.host,
            "port": self.config.port,
            "timestamp": datetime.now().isoformat(),
            "status": "failed",
            "error": None,
            "certificate_info": None
        }
        
        self.test_results["summary"]["total_tests"] += 1
        
        try:
            # Create SSL context with the trust store
            ssl_context = ssl.create_default_context(cafile=trust_store['path'])
            
            # Attempt to establish a connection
            with socket.create_connection((self.config.host, self.config.port)) as sock:
                with ssl_context.wrap_socket(sock, server_hostname=self.config.host) as ssock:
                    # Get server certificate info
                    cert_binary = ssock.getpeercert(binary_form=True)
                    x509 = crypto.load_certificate(crypto.FILETYPE_ASN1, cert_binary)
                    
                    # Extract certificate details
                    test_case["certificate_info"] = {
                        "subject": {k.decode(): v.decode() for k, v in x509.get_subject().get_components()},
                        "issuer": {k.decode(): v.decode() for k, v in x509.get_issuer().get_components()},
                        "serial_number": str(x509.get_serial_number()),
                        "not_before": x509.get_notBefore().decode(),
                        "not_after": x509.get_notAfter().decode(),
                        "protocol_version": ssock.version(),
                        "cipher_suite": ssock.cipher()[0]
                    }
                    
                    test_case["status"] = "passed"
                    self.test_results["summary"]["passed"] += 1
                    logger.info(f"✅ Webserver connection test PASSED using trust store {trust_store['path']}")
        
        except ssl.SSLError as e:
            test_case["error"] = f"SSL Error: {str(e)}"
            self.test_results["summary"]["failed"] += 1
            logger.error(f"❌ Webserver connection test FAILED using trust store {trust_store['path']}: {str(e)}")
        
        except Exception as e:
            test_case["error"] = f"Error: {str(e)}"
            self.test_results["summary"]["failed"] += 1
            logger.error(f"❌ Webserver connection test FAILED using trust store {trust_store['path']}: {str(e)}")
        
        self.test_results["webserver"].append(test_case)
        return test_case["status"] == "passed"
    
    def test_mtls_connection(self, trust_store):
        """Test MTLS connection to a server using the specified trust store and client certificates"""
        if not all([
            os.path.exists(self.config.client_cert),
            os.path.exists(self.config.client_key)
        ]):
            logger.warning(f"Skipping MTLS test - client cert or key not found")
            return False
        
        test_case = {
            "trust_store": trust_store['path'],
            "client_cert": self.config.client_cert,
            "client_key": self.config.client_key,
            "target": f"https://{self.config.host}:{self.config.port}/mtls",
            "timestamp": datetime.now().isoformat(),
            "status": "failed",
            "error": None,
            "response": None
        }
        
        self.test_results["summary"]["total_tests"] += 1
        
        try:
            # Make HTTPS request with client cert and custom CA
            response = requests.get(
                f"https://{self.config.host}:{self.config.port}/mtls",
                cert=(self.config.client_cert, self.config.client_key),
                verify=trust_store['path'],
                timeout=10
            )
            
            # Check if request was successful
            if response.status_code == 200:
                test_case["status"] = "passed"
                test_case["response"] = response.json()
                self.test_results["summary"]["passed"] += 1
                logger.info(f"✅ MTLS connection test PASSED using trust store {trust_store['path']}")
            else:
                test_case["error"] = f"HTTP Error: {response.status_code} - {response.text}"
                self.test_results["summary"]["failed"] += 1
                logger.error(f"❌ MTLS connection test FAILED using trust store {trust_store['path']}: HTTP {response.status_code}")
        
        except requests.exceptions.SSLError as e:
            test_case["error"] = f"SSL Error: {str(e)}"
            self.test_results["summary"]["failed"] += 1
            logger.error(f"❌ MTLS connection test FAILED using trust store {trust_store['path']}: {str(e)}")
        
        except Exception as e:
            test_case["error"] = f"Error: {str(e)}"
            self.test_results["summary"]["failed"] += 1
            logger.error(f"❌ MTLS connection test FAILED using trust store {trust_store['path']}: {str(e)}")
        
        self.test_results["mtls"].append(test_case)
        return test_case["status"] == "passed"
    
    def run_tests(self):
        """Run all validation tests"""
        logger.info(f"Starting trust chain validation tests")
        
        # Discover trust stores
        trust_stores = self.discover_trust_stores()
        if not trust_stores:
            logger.error("No trust stores found!")
            return False
        
        # Test each trust store for webserver and MTLS connections
        success = True
        for trust_store in trust_stores:
            # Test webserver connection
            if not self.test_webserver_connection(trust_store):
                success = False
            
            # Test MTLS connection if enabled
            if self.config.client_cert and self.config.client_key:
                if not self.test_mtls_connection(trust_store):
                    success = False
        
        # Update summary
        self.test_results["summary"]["end_time"] = datetime.now().isoformat()
        
        # Save results if output file is specified
        if self.config.output:
            with open(self.config.output, 'w') as f:
                json.dump(self.test_results, f, indent=2)
            logger.info(f"Test results saved to {self.config.output}")
        
        # Print summary
        summary = self.test_results["summary"]
        logger.info("="*50)
        logger.info(f"SUMMARY: {summary['passed']}/{summary['total_tests']} tests passed")
        logger.info(f"Webserver tests: {sum(1 for t in self.test_results['webserver'] if t['status'] == 'passed')}/{len(self.test_results['webserver'])} passed")
        logger.info(f"MTLS tests: {sum(1 for t in self.test_results['mtls'] if t['status'] == 'passed')}/{len(self.test_results['mtls'])} passed")
        logger.info("="*50)
        
        return success
    
    def generate_client_cert(self):
        """Generate client certificate for MTLS testing if it doesn't exist"""
        client_cert_dir = Path(self.config.client_cert).parent
        client_cert = Path(self.config.client_cert)
        client_key = Path(self.config.client_key)
        
        # Skip if files already exist
        if client_cert.exists() and client_key.exists():
            logger.info(f"Client certificates already exist at {client_cert}")
            return True
        
        # Create directory if it doesn't exist
        os.makedirs(client_cert_dir, exist_ok=True)
        
        try:
            # Create a key pair
            key = crypto.PKey()
            key.generate_key(crypto.TYPE_RSA, 2048)
            
            # Create a self-signed cert
            cert = crypto.X509()
            cert.get_subject().C = "US"
            cert.get_subject().ST = "California"
            cert.get_subject().L = "San Francisco"
            cert.get_subject().O = "Test Client"
            cert.get_subject().OU = "Testing"
            cert.get_subject().CN = "client.test"
            
            cert.set_serial_number(1000)
            cert.gmtime_adj_notBefore(0)
            cert.gmtime_adj_notAfter(10*365*24*60*60)  # 10 years
            
            cert.set_issuer(cert.get_subject())
            cert.set_pubkey(key)
            cert.sign(key, 'sha256')
            
            # Write certificate and key to files
            with open(client_cert, "wb") as f:
                f.write(crypto.dump_certificate(crypto.FILETYPE_PEM, cert))
            
            with open(client_key, "wb") as f:
                f.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, key))
            
            logger.info(f"Generated client certificate and key at {client_cert}")
            return True
            
        except Exception as e:
            logger.error(f"Error generating client certificate: {str(e)}")
            return False

def main():
    parser = argparse.ArgumentParser(description="Validate TLS trust chains")
    parser.add_argument("--scan-dir", "-d", required=True, 
                        help="Directory to scan for trust stores")
    parser.add_argument("--host", default="localhost", 
                        help="Host to connect to for testing (default: localhost)")
    parser.add_argument("--port", type=int, default=443, 
                        help="Port to connect to for testing (default: 443)")
    parser.add_argument("--client-cert", default="auto-trust-store-manager/test-suite/certs/client.crt",
                        help="Client certificate for MTLS testing")
    parser.add_argument("--client-key", default="auto-trust-store-manager/test-suite/certs/client.key",
                        help="Client key for MTLS testing")
    parser.add_argument("--output", "-o", 
                        help="Output file for test results (JSON format)")
    parser.add_argument("--verbose", "-v", action="store_true", 
                        help="Enable verbose output")
    
    args = parser.parse_args()
    
    # Set log level based on verbosity
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Initialize validator
    validator = TrustChainValidator(args)
    
    # Generate client certificate for MTLS testing
    validator.generate_client_cert()
    
    # Run tests
    success = validator.run_tests()
    
    # Exit with appropriate status code
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 