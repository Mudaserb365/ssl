# Trust Path Validator

This tool validates certificate chains to ensure they form a complete and trusted path from leaf certificates to trusted root CAs. It's a critical component of ensuring your PKI infrastructure is correctly configured.

## Features

- **Complete Chain Validation**: Verifies the entire certificate chain from leaf to root
- **Expiry Checks**: Warns about certificates that will expire soon
- **Multiple Root Stores**: Can validate against different root CA stores
- **Intermediate Support**: Handles intermediate certificates
- **Detailed Output**: Provides comprehensive information about the validation process

## Usage

```bash
go run trust-path-validator.go -cert /path/to/certificate.pem [options]
```

### Options

- `-cert`: Path to the certificate to validate (required)
- `-roots`: Path to the root CA certificates directory (default: `/etc/ssl/certs`)
- `-intermediates`: Optional path to intermediate certificates directory
- `-days`: Warn if certificate expires within this many days (default: 30)
- `-v`: Verbose output with detailed chain information
- `-json`: Output in JSON format (for integration with other tools)

## Examples

### Validate a website certificate

```bash
go run trust-path-validator.go -cert example.com.pem -v
```

### Validate against specific root store

```bash
go run trust-path-validator.go -cert client.crt -roots /path/to/custom/ca/store
```

### Include intermediate certificates

```bash
go run trust-path-validator.go -cert server.crt -intermediates /path/to/intermediates
```

## Output

The tool provides easily readable output indicating:

- Certificate subject and issuer information
- Validity period
- Chain validation status (✅ or ❌)
- Expiration warnings
- Detailed chain information in verbose mode

Example output:

```
Trust Path Validator
====================

Certificate: example.com
Issuer: Let's Encrypt Authority X3
Valid From: 2023-01-15T12:30:45Z
Valid Until: 2023-04-15T12:30:45Z

Chain Validation Result:
✅ Certificate has a valid trust path
✅ Complete certificate chain found
✅ Root certificate is trusted

Warnings:
⚠️ Certificate will expire in 25 days

Certificate Chain:
1. example.com (Issuer: Let's Encrypt Authority X3)
   Serial: 3B15AB08CD6221A4FF11F5F8
   Valid Until: 2023-04-15T12:30:45Z
2. Let's Encrypt Authority X3 (Issuer: DST Root CA X3)
   Serial: 0A0141420000015385736A0B85ECA708
   Valid Until: 2025-03-17T16:40:46Z
3. DST Root CA X3 (Issuer: DST Root CA X3)
   Serial: 44AFB080D6A327BA893039862EF8406B
   Valid Until: 2031-09-30T14:01:15Z
```

## Integration

This validator can be incorporated into:

- CI/CD pipelines to validate certificates before deployment
- Monitoring systems to check certificates regularly
- Security scanning tools to identify invalid or soon-to-expire certificates
- DevOps workflows to verify infrastructure security

## Building from Source

To build a standalone binary:

```bash
go build -o trust-path-validator trust-path-validator.go
```

## Future Enhancements

Planned features for future versions:

- OCSP/CRL revocation checking
- Extended Validation (EV) certificate verification
- Support for multiple certificate formats (DER, P12)
- Integration with certificate transparency logs
- Web interface for validation 