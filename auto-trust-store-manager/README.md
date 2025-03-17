# Auto Trust Store Manager

This project demonstrates automatic management of trust stores for Java (JKS) and Python (PEM) applications.

## Project Overview

The Auto Trust Store Manager provides scripts and applications to automatically update trust stores for both Java and Python applications. It ensures that all certificates in a baseline trust chain are included in the standard trust stores used by the applications.

## Components

- **Common Certificates**: Shared certificate files used by both Java and Python applications
- **Java Application**: A Spring Boot application that uses a JKS trust store
- **Python Application**: A Flask application that uses a PEM trust store
- **Trust Store Manager Scripts**: Shell scripts to update the trust stores
- **Test Cases**: Unit tests for both Java and Python implementations

## Directory Structure

```
auto-trust-store-manager/
├── common-certs/
│   ├── baseline-trust-chain.pem    # Contains trusted certificates that should always be included
│   ├── standard-trust-chain.pem    # PEM trust store for Python applications
│   └── standard-trust-store.jks    # JKS trust store for Java applications
├── java-app/
│   ├── auto-trust-store-manager.sh # Script to update the Java trust store
│   ├── TrustStoreTest.java         # Test case for the Java trust store
│   ├── pom.xml                     # Maven project file
│   └── src/                        # Java application source code
├── python-app/
│   ├── auto-trust-store-manager.sh # Script to update the Python trust store
│   ├── app.py                      # Flask application
│   ├── requirements.txt            # Python dependencies
│   └── test_trust_store.py         # Test case for the Python trust store
└── README.md                       # This file
```

## Certificate Files

- **baseline-trust-chain.pem**: Contains trusted certificates that should always be included in both trust stores
- **standard-trust-chain.pem**: The PEM trust store used by Python applications
- **standard-trust-store.jks**: The JKS trust store used by Java applications

## Auto Trust Store Manager Scripts

### Python

The Python auto trust store manager script (`python-app/auto-trust-store-manager.sh`) performs the following steps:

1. Checks if the standard PEM file exists, creating it if necessary
2. Copies the baseline trust chain to the standard trust chain
3. Counts and reports the number of certificates in the trust store

### Java

The Java auto trust store manager script (`java-app/auto-trust-store-manager.sh`) performs the following steps:

1. Checks if the standard JKS file exists, creating it if necessary
2. Extracts certificates from the baseline PEM file
3. Imports each certificate into the JKS trust store
4. Counts and reports the number of certificates in the trust store

## Test Cases

### Python

The Python test case (`python-app/test_trust_store.py`) verifies:

1. The standard trust store exists and contains certificates
2. The baseline trust store exists and contains certificates
3. All certificates in the baseline trust store are present in the standard trust store
4. The auto trust store manager script works correctly

### Java

The Java test case (`java-app/TrustStoreTest.java`) verifies:

1. The standard trust store exists and contains certificates
2. The auto trust store manager script works correctly

## Running the Applications

### Python

```bash
cd python-app
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py
```

The Python application will be available at http://localhost:5000

### Java

```bash
cd java-app
mvn spring-boot:run
```

The Java application will be available at http://localhost:8080

## Running the Tests

### Python

```bash
cd python-app
python -m unittest test_trust_store.py
```

### Java

```bash
cd java-app
javac TrustStoreTest.java
java TrustStoreTest
```

## Maintenance

To add new certificates to the trust stores:

1. Add the certificate to the `common-certs/baseline-trust-chain.pem` file
2. Run the appropriate auto trust store manager script:
   - For Python: `./python-app/auto-trust-store-manager.sh`
   - For Java: `./java-app/auto-trust-store-manager.sh` 