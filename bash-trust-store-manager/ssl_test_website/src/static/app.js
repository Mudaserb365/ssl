function formatCertificateForTerminal(certData) {
    if (!certData) return 'Certificate not available';

    return `Certificate:
    Data:
        Version: ${certData.version + 1} (0x${(certData.version + 1).toString(16)})
        Serial Number: ${certData.serial_number}
    Signature Algorithm: ${certData.signature_algorithm}
    Issuer: ${formatDN(certData.issuer)}
    Validity
        Not Before: ${certData.not_before}
        Not After : ${certData.not_after}
    Subject: ${formatDN(certData.subject)}`;
}

function formatDN(dn) {
    const order = ['C', 'ST', 'L', 'O', 'OU', 'CN'];
    const parts = [];
    
    for (const key of order) {
        if (dn[key]) {
            parts.push(`${key}=${dn[key]}`);
        }
    }
    
    // Add any remaining fields not in the order array
    for (const [key, value] of Object.entries(dn)) {
        if (!order.includes(key)) {
            parts.push(`${key}=${value}`);
        }
    }
    
    return parts.join(', ');
}

async function fetchCertificateInfo() {
    try {
        const response = await fetch('/api/cert-info');
        const data = await response.json();

        if (data.error) {
            throw new Error(data.error);
        }

        // Update server certificate
        const serverCertElement = document.getElementById('server-cert');
        serverCertElement.textContent = formatCertificateForTerminal(data.server_certificate);

        // Update intermediate CA certificate
        const intermediateCertElement = document.getElementById('intermediate-ca');
        if (data.intermediate_ca) {
            intermediateCertElement.textContent = formatCertificateForTerminal(data.intermediate_ca);
        } else {
            intermediateCertElement.textContent = 'Certificate not available';
        }

        // Update root CA certificate
        const rootCertElement = document.getElementById('root-ca');
        if (data.root_ca) {
            rootCertElement.textContent = formatCertificateForTerminal(data.root_ca);
        } else {
            rootCertElement.textContent = 'Certificate not available';
        }

        // Update protocol version
        const protocolVersionElement = document.getElementById('protocol-version');
        protocolVersionElement.textContent = `Protocol : ${data.protocol_version || 'Not available'}`;

    } catch (error) {
        console.error('Error fetching certificate info:', error);
        document.querySelectorAll('.output').forEach(pre => {
            if (pre.id !== 'protocol-version') {
                pre.textContent = `Error loading certificate information: ${error.message}`;
            } else {
                pre.textContent = `Error: ${error.message}`;
            }
        });
    }
}

// Fetch certificate information when the page loads
document.addEventListener('DOMContentLoaded', fetchCertificateInfo);

// Refresh certificate information every 5 minutes
setInterval(fetchCertificateInfo, 5 * 60 * 1000); 