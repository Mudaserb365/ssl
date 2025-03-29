package main

import (
	"crypto/x509"
	"encoding/pem"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type ValidationResult struct {
	Certificate     *x509.Certificate
	IsRoot          bool
	IsTrusted       bool
	IsIntermedidate bool
	IsValid         bool
	Errors          []string
}

type ChainValidationResult struct {
	LeafCertificate    *x509.Certificate
	Chain              []*x509.Certificate
	CompleteChain      bool
	ValidPath          bool
	RootTrusted        bool
	ExpirationWarnings []string
	Errors             []string
}

func main() {
	certFile := flag.String("cert", "", "Path to the certificate to validate")
	rootStore := flag.String("roots", "/etc/ssl/certs", "Path to the root CA certificates directory (default: /etc/ssl/certs)")
	intermediateDir := flag.String("intermediates", "", "Optional path to intermediate certificates directory")
	verbose := flag.Bool("v", false, "Verbose output")
	days := flag.Int("days", 30, "Warn if certificate expires within this many days")
	outputJson := flag.Bool("json", false, "Output in JSON format")
	flag.Parse()

	if *certFile == "" {
		fmt.Println("Error: You must specify a certificate to validate with -cert")
		flag.Usage()
		os.Exit(1)
	}

	fmt.Printf("Trust Path Validator\n")
	fmt.Printf("====================\n\n")

	// Read the certificate to validate
	certData, err := ioutil.ReadFile(*certFile)
	if err != nil {
		fmt.Printf("Error reading certificate: %v\n", err)
		os.Exit(1)
	}

	// Parse the certificate
	block, _ := pem.Decode(certData)
	if block == nil {
		fmt.Printf("Failed to parse certificate PEM data\n")
		os.Exit(1)
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		fmt.Printf("Error parsing certificate: %v\n", err)
		os.Exit(1)
	}

	// Build a root certificate pool
	rootPool := x509.NewCertPool()
	loadRoots(rootPool, *rootStore, *verbose)

	// Build intermediates pool if specified
	intermediatePool := x509.NewCertPool()
	if *intermediateDir != "" {
		loadRoots(intermediatePool, *intermediateDir, *verbose)
	}

	// Validate the certificate chain
	result := validateChain(cert, rootPool, intermediatePool, *days)

	// Display results
	if *outputJson {
		// Would format as JSON here
		fmt.Printf("JSON output not implemented yet\n")
	} else {
		displayChainResults(result, *verbose)
	}

	// Exit with error code if validation failed
	if !result.ValidPath {
		os.Exit(1)
	}
}

func loadRoots(pool *x509.CertPool, path string, verbose bool) {
	count := 0

	// Handle if path is a file or directory
	fileInfo, err := os.Stat(path)
	if err != nil {
		fmt.Printf("Error accessing root store path: %v\n", err)
		return
	}

	if !fileInfo.IsDir() {
		// Single file
		certData, err := ioutil.ReadFile(path)
		if err != nil {
			fmt.Printf("Error reading certificate file: %v\n", err)
			return
		}
		pool.AppendCertsFromPEM(certData)
		count = 1
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
				fmt.Printf("Warning: Could not read %s: %v\n", path, err)
				return nil
			}

			if pool.AppendCertsFromPEM(certData) {
				count++
			}
			return nil
		})

		if err != nil {
			fmt.Printf("Error walking root directory: %v\n", err)
		}
	}

	if verbose {
		fmt.Printf("Loaded %d certificates from %s\n", count, path)
	}
}

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

func displayChainResults(result ChainValidationResult, verbose bool) {
	fmt.Printf("Certificate: %s\n", result.LeafCertificate.Subject.CommonName)
	fmt.Printf("Issuer: %s\n", result.LeafCertificate.Issuer.CommonName)
	fmt.Printf("Valid From: %s\n", result.LeafCertificate.NotBefore.Format(time.RFC3339))
	fmt.Printf("Valid Until: %s\n", result.LeafCertificate.NotAfter.Format(time.RFC3339))

	fmt.Printf("\nChain Validation Result:\n")

	if result.ValidPath {
		fmt.Printf("✅ Certificate has a valid trust path\n")
	} else {
		fmt.Printf("❌ Certificate does NOT have a valid trust path\n")
	}

	if result.CompleteChain {
		fmt.Printf("✅ Complete certificate chain found\n")
	} else {
		fmt.Printf("❌ Incomplete certificate chain\n")
	}

	if result.RootTrusted {
		fmt.Printf("✅ Root certificate is trusted\n")
	} else {
		fmt.Printf("❌ Root certificate is NOT trusted\n")
	}

	if len(result.ExpirationWarnings) > 0 {
		fmt.Printf("\nWarnings:\n")
		for _, warning := range result.ExpirationWarnings {
			fmt.Printf("⚠️  %s\n", warning)
		}
	}

	if len(result.Errors) > 0 {
		fmt.Printf("\nErrors:\n")
		for _, err := range result.Errors {
			fmt.Printf("❌ %s\n", err)
		}
	}

	if verbose {
		fmt.Printf("\nCertificate Chain:\n")
		for i, cert := range result.Chain {
			fmt.Printf("%d. %s (Issuer: %s)\n", i+1, cert.Subject.CommonName, cert.Issuer.CommonName)
			fmt.Printf("   Serial: %X\n", cert.SerialNumber)
			fmt.Printf("   Valid Until: %s\n", cert.NotAfter.Format(time.RFC3339))
		}
	}
}
