# Trust Store Comparison and Update Tool

A bash script that searches for trust stores in a Python project, compares them with a standard trust store, and updates them based on the selected mode of operation.

## Usage

```bash
./compare_trust_stores.sh -s <standard_trust_store> [-d <project_directory>] [-e <extensions>] [-m <mode>]
```

### Parameters

- `-s`: Path to your standard trust store (PEM file) - required
- `-d`: Directory to search for trust stores (default: current directory)
- `-e`: Comma-separated list of file extensions to search for (default: pem,crt,cert)
- `-m`: Mode of operation (default: 1)
  - `1`: Compare and log differences only
  - `2`: Compare and append missing certificates
  - `3`: Compare and replace with standard trust store
- `-h`: Display help message

## Features

- Three operation modes:
  1. **Compare and Log**: Only logs differences without modifying files
  2. **Compare and Append**: Appends missing certificates from the standard trust store
  3. **Compare and Replace**: Replaces project trust stores with the standard trust store
- Searches for certificate files in a Python project
- Compares certificates with a standard trust store
- Creates detailed log files with comparison results
- Creates backups of all modified files with a `.bak` extension
- Handles multiple certificate formats (PEM, CRT, CERT) 