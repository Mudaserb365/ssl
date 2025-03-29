package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/mudaserb365/trust-store-manager/pkg/validator"
	"github.com/spf13/cobra"
)

// validateCmd represents the validate command
var validateCmd = &cobra.Command{
	Use:   "validate",
	Short: "Validate certificate trust chains",
	Long: `Validates the trust path of certificates to ensure they form a complete
and trusted chain from leaf certificates to trusted root CAs.

The validate command can validate individual certificate files or endpoints
such as websites and servers.`,
}

// validateFileCmd represents the validate file subcommand
var validateFileCmd = &cobra.Command{
	Use:   "file [certificate-file]",
	Short: "Validate a certificate file",
	Long: `Validates the trust path of a certificate file.

The certificate file should be in PEM format. This command will check
if the certificate forms a complete and trusted chain to a root CA.

Example:
  trust-store-manager validate file server.crt
  trust-store-manager validate file -r /path/to/roots client.pem`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		certFile := args[0]
		rootStore, _ := cmd.Flags().GetString("root-store")
		intermediates, _ := cmd.Flags().GetString("intermediates")
		days, _ := cmd.Flags().GetInt("days")
		verbose, _ := cmd.Flags().GetBool("verbose")

		// Check if file exists
		if _, err := os.Stat(certFile); os.IsNotExist(err) {
			fmt.Printf("Error: Certificate file does not exist: %s\n", certFile)
			os.Exit(1)
		}

		fmt.Println("Trust Path Validator")
		fmt.Println("====================")
		fmt.Println()

		// Validate the certificate
		result, err := validator.ValidateFile(certFile, rootStore, intermediates, days)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

		// Display the result
		fmt.Println(validator.FormatValidationResult(result, verbose))

		// Exit with status based on validation result
		if !result.ValidPath {
			os.Exit(1)
		}
	},
}

// validateDomainCmd represents the validate domain subcommand
var validateDomainCmd = &cobra.Command{
	Use:   "domain [hostname[:port]]",
	Short: "Validate a domain's certificate",
	Long: `Validates the trust path of a domain's certificate.

This command connects to the specified domain and validates its certificate
against trusted root CAs. The domain can include a port number, which
defaults to 443 if not specified.

Example:
  trust-store-manager validate domain example.com
  trust-store-manager validate domain example.com:8443`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		domain := args[0]
		rootStore, _ := cmd.Flags().GetString("root-store")
		intermediates, _ := cmd.Flags().GetString("intermediates")
		days, _ := cmd.Flags().GetInt("days")
		verbose, _ := cmd.Flags().GetBool("verbose")

		// Parse domain and port
		serverName := domain
		if strings.Contains(domain, ":") {
			parts := strings.Split(domain, ":")
			serverName = parts[0]
		} else {
			domain = domain + ":443"
		}

		fmt.Println("Trust Path Validator")
		fmt.Println("====================")
		fmt.Println()
		fmt.Printf("Domain: %s\n\n", serverName)

		// This would be implemented to fetch the certificate from the server
		fmt.Println("Endpoint validation not implemented in this example.")
		os.Exit(1)
	},
}

// validateDomainsCmd represents the validate domains subcommand
var validateDomainsCmd = &cobra.Command{
	Use:   "domains [domains-file]",
	Short: "Validate multiple domains' certificates",
	Long: `Validates the trust path of multiple domains' certificates.

The domains file should contain one domain per line. For each domain,
this command will connect to the domain and validate its certificate.

Example:
  trust-store-manager validate domains domains.txt
  trust-store-manager validate domains -o reports domains.txt`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		domainsFile := args[0]
		rootStore, _ := cmd.Flags().GetString("root-store")
		intermediates, _ := cmd.Flags().GetString("intermediates")
		days, _ := cmd.Flags().GetInt("days")
		outputDir, _ := cmd.Flags().GetString("output-dir")
		summaryOnly, _ := cmd.Flags().GetBool("summary")

		// Check if file exists
		if _, err := os.Stat(domainsFile); os.IsNotExist(err) {
			fmt.Printf("Error: Domains file does not exist: %s\n", domainsFile)
			os.Exit(1)
		}

		// Create output directory if it doesn't exist
		if outputDir != "" {
			if err := os.MkdirAll(outputDir, 0755); err != nil {
				fmt.Printf("Error creating output directory: %v\n", err)
				os.Exit(1)
			}
		}

		fmt.Println("Trust Path Validator - Bulk Domain Validation")
		fmt.Println("=============================================")
		fmt.Println()

		// This would be implemented to read the domains file and validate each domain
		fmt.Println("Bulk domain validation not implemented in this example.")
		os.Exit(1)
	},
}

// init initializes the validate command and its subcommands
func init() {
	rootCmd.AddCommand(validateCmd)
	validateCmd.AddCommand(validateFileCmd)
	validateCmd.AddCommand(validateDomainCmd)
	validateCmd.AddCommand(validateDomainsCmd)

	// Add flags to validateFileCmd
	validateFileCmd.Flags().StringP("root-store", "r", "/etc/ssl/certs", "Path to the root CA certificates directory")
	validateFileCmd.Flags().StringP("intermediates", "i", "", "Path to intermediate certificates directory")
	validateFileCmd.Flags().IntP("days", "d", 30, "Warn if certificate expires within this many days")
	validateFileCmd.Flags().BoolP("verbose", "v", false, "Show verbose output")

	// Add flags to validateDomainCmd
	validateDomainCmd.Flags().StringP("root-store", "r", "/etc/ssl/certs", "Path to the root CA certificates directory")
	validateDomainCmd.Flags().StringP("intermediates", "i", "", "Path to intermediate certificates directory")
	validateDomainCmd.Flags().IntP("days", "d", 30, "Warn if certificate expires within this many days")
	validateDomainCmd.Flags().BoolP("verbose", "v", false, "Show verbose output")

	// Add flags to validateDomainsCmd
	validateDomainsCmd.Flags().StringP("root-store", "r", "/etc/ssl/certs", "Path to the root CA certificates directory")
	validateDomainsCmd.Flags().StringP("intermediates", "i", "", "Path to intermediate certificates directory")
	validateDomainsCmd.Flags().IntP("days", "d", 30, "Warn if certificate expires within this many days")
	validateDomainsCmd.Flags().StringP("output-dir", "o", "", "Directory to save validation reports")
	validateDomainsCmd.Flags().BoolP("summary", "s", false, "Show only summary results")
}
