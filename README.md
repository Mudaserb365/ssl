# Trust Store Comparison and Update Tool

A bash script that searches for trust stores in a Python project, compares them with a standard trust store, and updates them by appending missing certificates.

## Usage

```bash
./compare_trust_stores.sh -s <standard_trust_store> [-d <project_directory>] [-e <extensions>]
```

### Parameters

- `-s`: Path to your standard trust store (PEM file) - required
- `-d`: Directory to search for trust stores (default: current directory)
- `-e`: Comma-separated list of file extensions to search for (default: pem,crt,cert)
- `-h`: Display help message

## Features

- Searches for certificate files in a Python project
- Compares certificates with a standard trust store
- Updates project trust stores by appending missing certificates
- Creates backups of all modified files with a `.bak` extension
- Handles multiple certificate formats (PEM, CRT, CERT) 