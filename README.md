# Trust Store Comparison and Update Tools

A set of bash scripts that search for trust stores in a project, compare them with a standard trust store, and update them based on the selected mode of operation.

## Scripts

- **compare_trust_stores.sh**: For PEM, CRT, and CERT trust stores
- **compare_jks_stores.sh**: For Java KeyStore (JKS) trust stores using keytool
- **docker_trust_store_update.sh**: For finding and updating trust stores in Docker containers

## Usage

### For PEM/CRT/CERT Trust Stores

```bash
./compare_trust_stores.sh -s <standard_trust_store> [-d <project_directory>] [-e <extensions>] [-m <mode>] [-u <url>]
```

### For JKS Trust Stores

```bash
./compare_jks_stores.sh -s <standard_trust_store> [-p <password>] [-d <project_directory>] [-m <mode>] [-u <url>]
```

### For Docker Containers

```bash
./docker_trust_store_update.sh -s <standard_trust_store> -c <container_id> [-p <path_in_container>] [-m <mode>] [-u <url>]
```

## Parameters

### Common Parameters

- `-s`: Path to your standard trust store - required if `-u` is not used
- `-u`: URL to download standard trust store - required if `-s` is not used
- `-m`: Mode of operation
  - `1`: Compare and log differences only
  - `2`: Compare and append missing certificates
  - `3`: Compare and replace with standard trust store
- `-h`: Display help message

### PEM/CRT/CERT Specific Parameters

- `-d`: Directory to search for trust stores (default: current directory)
- `-e`: Comma-separated list of file extensions to search for (default: pem,crt,cert)
- Default mode: `2` (Compare and append)

### JKS Specific Parameters

- `-d`: Directory to search for trust stores (default: current directory)
- `-p`: Password for the JKS trust stores (default: changeit)
- Default mode: `2` (Compare and append)

### Docker Specific Parameters

- `-c`: Docker container ID or name - required
- `-p`: Path in container to search for trust stores (default: /)
- Default mode: `2` (Compare and append)

## Features

- Three operation modes:
  1. **Compare and Log**: Only logs differences without modifying files
     - Generates an executable script with commands to fix trust stores
     - Provides both append and replace options in the generated script
  2. **Compare and Append**: Appends missing certificates from the standard trust store
  3. **Compare and Replace**: Replaces project trust stores with the standard trust store
- Flexible trust store source options:
  - Local file path
  - Remote URL (downloaded via HTTP GET)
- Searches for certificate files in:
  - Local filesystem
  - Java KeyStores
  - Docker containers
- Compares certificates with a standard trust store
- Creates detailed log files with comparison results
- Creates backups of all modified files with a `.bak` extension
- Handles multiple certificate formats (PEM, CRT, CERT, JKS) 