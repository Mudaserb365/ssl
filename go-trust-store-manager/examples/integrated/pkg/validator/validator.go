package validator

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ValidationResult represents the validation status of a single certificate
type ValidationResult struct {
	Certificate    *x509.Certificate
	IsRoot         bool
	IsTrusted      bool
	IsIntermediate bool
	IsValid        bool
	Errors         []string
}

// ChainValidationResult represents the validation status of a certificate chain
type ChainValidationResult struct {
	LeafCertificate    *x509.Certificate
	Chain              []*x509.Certificate
	CompleteChain      bool
	ValidPath          bool
	RootTrusted        bool
	ExpirationWarnings []string
	Errors             []string
}

// ValidateFile validates a certificate file and returns the validation result
func ValidateFile(certFile string, rootStorePath string, intermediatePath string, expiryDays int) (*ChainValidationResult, error) {
	// Read the certificate to validate
	certData, err := ioutil.ReadFile(certFile)
	if err != nil {
		return nil, fmt.Errorf("error reading certificate: %v", err)
	}

	// Parse the certificate
	block, _ := pem.Decode(certData)
	if block == nil {
		return nil, fmt.Errorf("failed to parse certificate PEM data")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("error parsing certificate: %v", err)
	}

	// Build a root certificate pool
	rootPool := x509.NewCertPool()
	if err := loadRoots(rootPool, rootStorePath, false); err != nil {
		return nil, fmt.Errorf("error loading root certificates: %v", err)
	}

	// Build intermediates pool if specified
	intermediatePool := x509.NewCertPool()
	if intermediatePath != "" {
		if err := loadRoots(intermediatePool, intermediatePath, false); err != nil {
			return nil, fmt.Errorf("error loading intermediate certificates: %v", err)
		}
	}

	// Validate the certificate chain
	result := validateChain(cert, rootPool, intermediatePool, expiryDays)
	return &result, nil
}

// ValidateEndpoint validates a server certificate from a host:port endpoint
func ValidateEndpoint(endpoint string, serverName string, rootStorePath string, intermediatePath string, expiryDays int) (*ChainValidationResult, error) {
	// This would use crypto/tls to connect to the endpoint and get the certificate
	// For simplicity in this example, we'll return a placeholder
	return nil, fmt.Errorf("endpoint validation not implemented yet")
}

// loadRoots loads root certificates from a file or directory into a certificate pool
func loadRoots(pool *x509.CertPool, path string, verbose bool) error {
	count := 0

	// Handle if path is a file or directory
	fileInfo, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("error accessing path: %v", err)
	}

	if !fileInfo.IsDir() {
		// Single file
		certData, err := ioutil.ReadFile(path)
		if err != nil {
			return fmt.Errorf("error reading certificate file: %v", err)
		}
		if !pool.AppendCertsFromPEM(certData) {
			return fmt.Errorf("failed to parse certificates from %s", path)
		}
	} else {
		// Directory
		err := filepath.Walk(path, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}

			// Skip directories and non-certificate files
			if info.IsDir() {
				return nil
			}

			ext := strings.ToLower(filepath.Ext(path))
			if ext != ".pem" && ext != ".crt" && ext != ".cert" {
				return nil
			}

			certData, err := ioutil.ReadFile(path)
			if err != nil {
				if verbose {
					fmt.Printf("Warning: Could not read %s: %v\n", path, err)
				}
				return nil
			}

			if pool.AppendCertsFromPEM(certData) {
				count++
			}
			return nil
		})

		if err != nil {
			return fmt.Errorf("error walking directory: %v", err)
		}
	}

	if verbose {
		fmt.Printf("Loaded %d certificates from %s\n", count, path)
	}

	return nil
}

// validateChain validates a certificate chain against root and intermediate certificate pools
func validateChain(cert *x509.Certificate, roots *x509.CertPool, intermediates *x509.CertPool, expiryDays int) ChainValidationResult {
	result := ChainValidationResult{
		LeafCertificate: cert,
		Chain:           []*x509.Certificate{cert},
		CompleteChain:   false,
		ValidPath:       false,
		RootTrusted:     false,
	}

	// Expiry check
	now := time.Now()
	if cert.NotAfter.Before(now) {
		result.Errors = append(result.Errors, "Certificate has expired")
	} else {
		expiryWarningDate := now.Add(time.Duration(expiryDays) * 24 * time.Hour)
		if cert.NotAfter.Before(expiryWarningDate) {
			daysUntilExpiry := int(cert.NotAfter.Sub(now).Hours() / 24)
			result.ExpirationWarnings = append(result.ExpirationWarnings,
				fmt.Sprintf("Certificate will expire in %d days", daysUntilExpiry))
		}
	}

	// Check if it's not yet valid
	if cert.NotBefore.After(now) {
		result.Errors = append(result.Errors, "Certificate is not yet valid")
	}

	// Verify certificate chain
	opts := x509.VerifyOptions{
		Roots:         roots,
		Intermediates: intermediates,
		CurrentTime:   now,
	}

	chains, err := cert.Verify(opts)
	if err != nil {
		result.Errors = append(result.Errors, fmt.Sprintf("Chain verification failed: %v", err))
		return result
	}

	// We have at least one valid chain
	result.ValidPath = true

	// Use the first chain found
	if len(chains) > 0 && len(chains[0]) > 0 {
		result.Chain = chains[0]
		result.CompleteChain = true

		// Check if the root is trusted
		root := chains[0][len(chains[0])-1]
		// If a certificate is self-signed, it might be a root
		isSelfSigned := root.IsCA &&
			root.CheckSignature(root.SignatureAlgorithm, root.RawTBSCertificate, root.Signature) == nil

		if isSelfSigned {
			result.RootTrusted = true
		}
	}

	return result
}

// FormatValidationResult formats a validation result for display
func FormatValidationResult(result *ChainValidationResult, verbose bool) string {
	var output strings.Builder

	// Basic certificate info
	fmt.Fprintf(&output, "Certificate: %s\n", result.LeafCertificate.Subject.CommonName)
	fmt.Fprintf(&output, "Issuer: %s\n", result.LeafCertificate.Issuer.CommonName)
	fmt.Fprintf(&output, "Valid From: %s\n", result.LeafCertificate.NotBefore.Format(time.RFC3339))
	fmt.Fprintf(&output, "Valid Until: %s\n", result.LeafCertificate.NotAfter.Format(time.RFC3339))

	fmt.Fprintf(&output, "\nChain Validation Result:\n")

	if result.ValidPath {
		fmt.Fprintf(&output, "✅ Certificate has a valid trust path\n")
	} else {
		fmt.Fprintf(&output, "❌ Certificate does NOT have a valid trust path\n")
	}

	if result.CompleteChain {
		fmt.Fprintf(&output, "✅ Complete certificate chain found\n")
	} else {
		fmt.Fprintf(&output, "❌ Incomplete certificate chain\n")
	}

	if result.RootTrusted {
		fmt.Fprintf(&output, "✅ Root certificate is trusted\n")
	} else {
		fmt.Fprintf(&output, "❌ Root certificate is NOT trusted\n")
	}

	if len(result.ExpirationWarnings) > 0 {
		fmt.Fprintf(&output, "\nWarnings:\n")
		for _, warning := range result.ExpirationWarnings {
			fmt.Fprintf(&output, "⚠️  %s\n", warning)
		}
	}

	if len(result.Errors) > 0 {
		fmt.Fprintf(&output, "\nErrors:\n")
		for _, err := range result.Errors {
			fmt.Fprintf(&output, "❌ %s\n", err)
		}
	}

	if verbose {
		fmt.Fprintf(&output, "\nCertificate Chain:\n")
		for i, cert := range result.Chain {
			fmt.Fprintf(&output, "%d. %s (Issuer: %s)\n", i+1, cert.Subject.CommonName, cert.Issuer.CommonName)
			fmt.Fprintf(&output, "   Serial: %X\n", cert.SerialNumber)
			fmt.Fprintf(&output, "   Valid Until: %s\n", cert.NotAfter.Format(time.RFC3339))
		}
	}

	return output.String()
}
