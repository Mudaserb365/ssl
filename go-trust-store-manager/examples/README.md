# Trust Store Manager Examples

This directory contains example trust stores and certificates for testing purposes.

## Sample Files

- `sample.pem` - A sample PEM certificate bundle
- `sample.jks` - A sample Java KeyStore (password: "changeit")
- `sample.p12` - A sample PKCS12 KeyStore (password: "changeit")

## Using Examples

You can use these example files to test the Trust Store Manager without modifying your real trust stores:

```bash
# Scan the examples directory
../bin/trust-store-manager-darwin-amd64 -d . --scan-only

# Add a certificate to the sample trust stores
../bin/trust-store-manager-darwin-amd64 -d . -c sample.pem -p "changeit"
```

## Creating Test Projects

You can create test project directories with the following structure:

```
project-java/
  ├── src/
  │   └── main/
  │       └── resources/
  │           └── truststore.jks
  ├── config/
  │   └── security/
  │       └── cacerts
  └── pom.xml

project-python/
  ├── certificates/
  │   └── ca-bundle.pem
  ├── requirements.txt
  └── setup.py

project-nodejs/
  ├── certs/
  │   └── ca-certificates.crt
  ├── package.json
  └── node_modules/
```

The Trust Store Manager will automatically detect these projects and find the appropriate trust stores. 