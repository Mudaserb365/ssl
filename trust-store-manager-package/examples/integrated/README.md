# Integrated MRP (Managed Root Program)

This example demonstrates how to create a unified, standalone executable that integrates the trust path validator as a subcommand within the MRP application.

## Architecture

The integrated MRP is built with a modular architecture:

```
cmd/mrp/                   # Main application entry point
pkg/
  ├── cmd/                  # Command-line interface
  │    ├── root.go          # Root command and shared flags
  │    ├── validate.go      # Certificate validation commands
  │    ├── update.go        # Trust store update commands (not included in example)
  │    └── scan.go          # Trust store scanning commands (not included in example)
  ├── validator/            # Certificate validation package
  │    └── validator.go     # Core validation functionality
  ├── manager/              # Trust store management package (not included in example)
  └── common/               # Shared utilities (not included in example)
```

## Command Structure

The application provides a hierarchical command structure:

```
mrp
  ├── validate              # Certificate validation commands
  │    ├── file             # Validate a certificate file
  │    ├── domain           # Validate a domain's certificate
  │    └── domains          # Validate multiple domains (batch mode)
  ├── scan                  # Scan for trust stores (not implemented in example)
  └── update                # Update trust stores (not implemented in example)
```

## Example Usage

### Validating a Certificate File

```bash
mrp validate file server.crt
```

### Validating a Domain's Certificate

```bash
mrp validate domain example.com
```

### Validating Multiple Domains

```bash
mrp validate domains domains.txt -o reports
```

## Building

To build the standalone executable:

```bash
cd cmd/mrp
go build -o mrp
```

## Dependencies

- [github.com/spf13/cobra](https://github.com/spf13/cobra) - A Commander for modern Go CLI applications

## Extending

This integrated approach makes it easy to add new commands and functionality:

1. Create a new command file in `pkg/cmd/` (e.g., `monitor.go` for certificate monitoring)
2. Add the implementation in a corresponding package (e.g., `pkg/monitor/`)
3. Register the command in its `init()` function using `rootCmd.AddCommand()`

## Benefits of Integration

By integrating the trust path validator into the main application:

1. **Unified User Experience** - Users have a single tool to learn and remember
2. **Shared Code** - Core validation logic can be reused across commands
3. **Consistent Interface** - All commands follow the same patterns and styles
4. **Reduced Dependencies** - A single executable with all capabilities
5. **Simplified Deployment** - Only one binary to distribute and manage 