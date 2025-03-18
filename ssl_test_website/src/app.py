from flask import Flask, jsonify, request
from OpenSSL import crypto
import datetime
import socket
import ssl
import hashlib
import os
import json

app = Flask(__name__)

def get_certificate_details(cert):
    """Extract details from a certificate object."""
    subject = {k.decode('utf-8'): v.decode('utf-8') 
              for k, v in cert.get_subject().get_components()}
    issuer = {k.decode('utf-8'): v.decode('utf-8') 
             for k, v in cert.get_issuer().get_components()}
    
    # Extract extensions if available
    extensions = {}
    for i in range(cert.get_extension_count()):
        try:
            ext = cert.get_extension(i)
            ext_name = ext.get_short_name().decode('utf-8')
            ext_data = str(ext)
            extensions[ext_name] = ext_data
        except Exception as e:
            print(f"Error extracting extension {i}: {str(e)}")
    
    # Calculate fingerprint
    fingerprint = cert.digest('sha256').decode('ascii')
    
    return {
        'subject': subject,
        'issuer': issuer,
        'version': cert.get_version(),
        'serial_number': str(cert.get_serial_number()),
        'not_before': datetime.datetime.strptime(
            cert.get_notBefore().decode('ascii'),
            '%Y%m%d%H%M%SZ'
        ).strftime('%Y-%m-%d %H:%M:%S UTC'),
        'not_after': datetime.datetime.strptime(
            cert.get_notAfter().decode('ascii'),
            '%Y%m%d%H%M%SZ'
        ).strftime('%Y-%m-%d %H:%M:%S UTC'),
        'signature_algorithm': cert.get_signature_algorithm().decode('ascii'),
        'extensions': extensions,
        'fingerprint': fingerprint
    }

def get_certificate_chain_info():
    try:
        # Read server certificate
        with open('/etc/nginx/ssl/server.crt', 'rb') as f:
            server_cert_data = f.read()
            server_cert = crypto.load_certificate(crypto.FILETYPE_PEM, server_cert_data)
        
        # Try to read certificate chain, but don't fail if it's not available
        intermediate_ca = None
        root_ca = None
        try:
            with open('/etc/nginx/ssl/chain.crt', 'rb') as f:
                chain_data = f.read()
                certs = []
                current = chain_data
                while current:
                    cert = crypto.load_certificate(crypto.FILETYPE_PEM, current)
                    certs.append(cert)
                    # Get the remaining data after the current certificate
                    current = current[current.find(b'-----BEGIN CERTIFICATE-----', 1):]
                    if not b'-----BEGIN CERTIFICATE-----' in current:
                        break
                
                if len(certs) > 0:
                    intermediate_ca = get_certificate_details(certs[0])
                if len(certs) > 1:
                    root_ca = get_certificate_details(certs[1])
        except FileNotFoundError:
            # Chain file not found, we'll just show the server certificate
            pass
        except Exception as e:
            print(f"Error reading chain file: {str(e)}")
        
        # Get SSL/TLS protocol version and cipher suite
        protocol_version = None
        cipher_suite = None
        try:
            context = ssl._create_unverified_context()
            with socket.create_connection(('127.0.0.1', 443)) as sock:
                with context.wrap_socket(sock, server_hostname='localhost') as ssock:
                    protocol_version = ssock.version()
                    cipher_suite = ssock.cipher()[0]
        except Exception as e:
            protocol_version = f"Error getting protocol version: {str(e)}"
        
        # Calculate chain length
        chain_length = 1
        if intermediate_ca:
            chain_length += 1
        if root_ca:
            chain_length += 1
        
        # Read CA Trust Store
        ca_trust_store = None
        try:
            with open('/etc/nginx/ssl/ca-trust-store.pem', 'rb') as f:
                ca_data = f.read()
                if ca_data:
                    ca_certs = []
                    current = ca_data
                    while current:
                        try:
                            cert = crypto.load_certificate(crypto.FILETYPE_PEM, current)
                            ca_certs.append(get_certificate_details(cert))
                            # Get the remaining data after the current certificate
                            next_pos = current.find(b'-----BEGIN CERTIFICATE-----', 1)
                            if next_pos == -1:
                                break
                            current = current[next_pos:]
                        except Exception:
                            break
                    ca_trust_store = ca_certs
        except FileNotFoundError:
            # Trust store file not found
            pass
        except Exception as e:
            print(f"Error reading CA trust store: {str(e)}")
        
        # Build certificate chain information
        chain_info = {
            'server_certificate': get_certificate_details(server_cert),
            'intermediate_ca': intermediate_ca,
            'root_ca': root_ca,
            'protocol_version': protocol_version,
            'cipher_suite': cipher_suite,
            'chain_length': chain_length,
            'ca_trust_store': ca_trust_store
        }
        
        return chain_info
    except Exception as e:
        return {'error': str(e)}

def get_client_cert_info():
    """Extract client certificate information from request headers."""
    client_info = {
        'has_client_cert': False,
        'client_verify': request.headers.get('X-SSL-Client-Verify', 'None'),
        'client_dn': request.headers.get('X-SSL-Client-DN', 'None')
    }
    
    if client_info['client_verify'] == 'SUCCESS':
        client_info['has_client_cert'] = True
    
    return client_info

@app.route('/api/cert-info')
def cert_info():
    return jsonify(get_certificate_chain_info())

@app.route('/mtls')
def mtls_info():
    """Endpoint for displaying MTLS connection information."""
    cert_chain = get_certificate_chain_info()
    client_cert = get_client_cert_info()
    
    result = {
        'server_certificate': cert_chain.get('server_certificate'),
        'ca_trust_store': cert_chain.get('ca_trust_store'),
        'client_certificate': client_cert
    }
    
    return jsonify(result)

@app.route('/api/status')
def status():
    """Simple endpoint to check if the API is running."""
    return jsonify({
        'status': 'ok',
        'timestamp': datetime.datetime.now().isoformat()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000) 