function formatCertificate(certData, title) {
    if (!certData) return `<div class="cert-heading">${title}</div><div class="property-value">Certificate not available</div>`;

    // Try to extract key usage if available
    let keyUsage = '';
    try {
        if (certData.extensions && certData.extensions.keyUsage) {
            keyUsage = createPropertyRow('Key Usage', certData.extensions.keyUsage);
        }
    } catch (e) {
        console.error('Error extracting key usage:', e);
    }

    // Try to extract SAN if available
    let san = '';
    try {
        if (certData.extensions && certData.extensions.subjectAltName) {
            san = createPropertyRow('Subject Alternative Names', certData.extensions.subjectAltName);
        }
    } catch (e) {
        console.error('Error extracting SAN:', e);
    }

    return `
        <div class="cert-heading">${title}</div>
        ${createPropertyRow('Version', certData.version + 1)}
        ${createPropertyRow('Serial Number', certData.serial_number)}
        ${createPropertyRow('Signature Algorithm', certData.signature_algorithm)}
        ${createPropertyRow('Issuer', formatDN(certData.issuer))}
        ${createPropertyRow('Valid From', certData.not_before)}
        ${createPropertyRow('Valid Until', certData.not_after)}
        ${createPropertyRow('Subject', formatDN(certData.subject))}
        ${keyUsage}
        ${san}
        ${createPropertyRow('Fingerprint', certData.fingerprint || 'Not available')}
    `;
}

function createPropertyRow(name, value) {
    return `<div><span class="property-name">${name}:</span> <span class="property-value">${value}</span></div>`;
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
        serverCertElement.innerHTML = formatCertificate(data.server_certificate, 'SERVER CERTIFICATE');

        // Update intermediate CA certificate
        const intermediateCertElement = document.getElementById('intermediate-ca');
        if (data.intermediate_ca) {
            intermediateCertElement.innerHTML = formatCertificate(data.intermediate_ca, 'INTERMEDIATE CA CERTIFICATE');
        } else {
            intermediateCertElement.innerHTML = formatCertificate(null, 'INTERMEDIATE CA CERTIFICATE');
        }

        // Update root CA certificate
        const rootCertElement = document.getElementById('root-ca');
        if (data.root_ca) {
            rootCertElement.innerHTML = formatCertificate(data.root_ca, 'ROOT CA CERTIFICATE');
        } else {
            rootCertElement.innerHTML = formatCertificate(null, 'ROOT CA CERTIFICATE');
        }

        // Update protocol version
        const protocolInfoElement = document.getElementById('protocol-info');
        protocolInfoElement.innerHTML = `
            <div class="cert-heading">CONNECTION INFORMATION</div>
            ${createPropertyRow('SSL/TLS Protocol', data.protocol_version || 'Not available')}
            ${createPropertyRow('Cipher Suite', data.cipher_suite || 'Not available')}
            ${createPropertyRow('Certificate Chain Length', data.chain_length || (data.intermediate_ca && data.root_ca ? '3' : (data.intermediate_ca ? '2' : '1')))}
        `;

    } catch (error) {
        console.error('Error fetching certificate info:', error);
        document.querySelectorAll('#server-cert, #intermediate-ca, #root-ca, #protocol-info').forEach(element => {
            element.innerHTML = `<div class="cert-heading">ERROR</div><div class="property-value">Error loading certificate information: ${error.message}</div>`;
        });
    }
}

// Fetch certificate information when the page loads
document.addEventListener('DOMContentLoaded', fetchCertificateInfo);

// Refresh certificate information every 5 minutes
setInterval(fetchCertificateInfo, 5 * 60 * 1000); 