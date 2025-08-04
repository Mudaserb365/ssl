package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// exportJksCertificates exports all certificates from a JKS file to PEM format
func exportJksCertificates(jksPath, password, outputDir string) ([]string, error) {
	var certFiles []string

	// Find keytool
	keytoolPath, err := findKeytool()
	if err != nil {
		return nil, err
	}

	// List all entries in the keystore
	listCmd := exec.Command(
		keytoolPath,
		"-list",
		"-keystore", jksPath,
		"-storepass", password,
		"-v",
	)

	output, err := listCmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to list keystore entries: %v", err)
	}

	// Parse the output to find aliases
	lines := strings.Split(string(output), "\n")
	var aliases []string
	currentAlias := ""

	for _, line := range lines {
		if strings.HasPrefix(line, "Alias name:") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) > 1 {
				currentAlias = strings.TrimSpace(parts[1])
				aliases = append(aliases, currentAlias)
			}
		}
	}

	// Export each certificate
	for _, alias := range aliases {
		certFile := filepath.Join(outputDir, fmt.Sprintf("%s.pem", alias))

		exportCmd := exec.Command(
			keytoolPath,
			"-exportcert",
			"-keystore", jksPath,
			"-storepass", password,
			"-alias", alias,
			"-rfc",
			"-file", certFile,
		)

		err := exportCmd.Run()
		if err != nil {
			continue // Skip this entry if export fails
		}

		certFiles = append(certFiles, certFile)
	}

	return certFiles, nil
}

// extractPemCertificates extracts individual certificates from a PEM bundle
func extractPemCertificates(pemPath, outputDir string) ([]string, error) {
	var certFiles []string

	// Read the PEM file
	pemData, err := os.ReadFile(pemPath)
	if err != nil {
		return nil, err
	}

	// Split the PEM file into individual certificates
	pemStr := string(pemData)
	certBlocks := strings.Split(pemStr, "-----BEGIN CERTIFICATE-----")

	for i, block := range certBlocks {
		if i == 0 && !strings.Contains(block, "-----END CERTIFICATE-----") {
			// Skip the first block if it doesn't contain a certificate
			continue
		}

		// Reconstruct the certificate block
		certStr := "-----BEGIN CERTIFICATE-----" + block
		certStr = strings.TrimSpace(certStr)

		// Skip if this isn't a complete certificate block
		if !strings.Contains(certStr, "-----END CERTIFICATE-----") {
			continue
		}

		// Write the certificate to a file
		certFile := filepath.Join(outputDir, fmt.Sprintf("cert_%d.pem", i))
		err := os.WriteFile(certFile, []byte(certStr), 0644)
		if err != nil {
			continue // Skip this certificate if writing fails
		}

		certFiles = append(certFiles, certFile)
	}

	return certFiles, nil
}

// extractPkcs12Certificates extracts certificates from a PKCS12 file
func extractPkcs12Certificates(pkcs12Path, password, outputDir string) ([]string, error) {
	var certFiles []string

	// Extract to a single PEM file first
	tempPem := filepath.Join(outputDir, "temp.pem")

	extractCmd := exec.Command(
		"openssl", "pkcs12",
		"-in", pkcs12Path,
		"-nokeys",
		"-passin", fmt.Sprintf("pass:%s", password),
		"-out", tempPem,
	)

	err := extractCmd.Run()
	if err != nil {
		return nil, fmt.Errorf("failed to extract certificates from PKCS12: %v", err)
	}

	// Now extract individual certificates from the PEM file
	certFiles, err = extractPemCertificates(tempPem, outputDir)

	// Clean up the temporary file
	os.Remove(tempPem)

	return certFiles, err
}

// getCertificateFingerprint gets the SHA-256 fingerprint of a certificate
func getCertificateFingerprint(certPath string) (string, error) {
	cmd := exec.Command(
		"openssl", "x509",
		"-in", certPath,
		"-fingerprint",
		"-sha256",
		"-noout",
	)

	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get certificate fingerprint: %v", err)
	}

	// Parse the fingerprint from the output
	// Output format: SHA256 Fingerprint=XX:XX:XX:...
	fingerprint := strings.TrimSpace(string(output))
	parts := strings.SplitN(fingerprint, "=", 2)
	if len(parts) < 2 {
		return "", fmt.Errorf("invalid fingerprint format")
	}

	return strings.TrimSpace(parts[1]), nil
}

// getCertificateSubject gets the subject of a certificate
func getCertificateSubject(certPath string) (string, error) {
	cmd := exec.Command(
		"openssl", "x509",
		"-in", certPath,
		"-subject",
		"-noout",
	)

	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get certificate subject: %v", err)
	}

	// Parse the subject from the output
	// Output format: subject=xxx
	subject := strings.TrimSpace(string(output))
	parts := strings.SplitN(subject, "=", 2)
	if len(parts) < 2 {
		return "", fmt.Errorf("invalid subject format")
	}

	return strings.TrimSpace(parts[1]), nil
}

// importCertificateToJks imports a certificate to a JKS file
func importCertificateToJks(certPath, jksPath, password, alias string) error {
	// Find keytool
	keytoolPath, err := findKeytool()
	if err != nil {
		return err
	}

	// Import the certificate
	importCmd := exec.Command(
		keytoolPath,
		"-importcert",
		"-noprompt",
		"-keystore", jksPath,
		"-storepass", password,
		"-alias", alias,
		"-file", certPath,
	)

	return importCmd.Run()
}

// createEmptyPemFile creates an empty PEM file
func createEmptyPemFile(filePath string) error {
	// Create the directory if it doesn't exist
	dir := filepath.Dir(filePath)
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		err := os.MkdirAll(dir, 0755)
		if err != nil {
			return err
		}
	}

	// Create an empty file
	file, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	return nil
}

// createEmptyJksFile creates an empty JKS file
func createEmptyJksFile(filePath, password string) error {
	// Find keytool
	keytoolPath, err := findKeytool()
	if err != nil {
		return err
	}

	// Create the directory if it doesn't exist
	dir := filepath.Dir(filePath)
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		err := os.MkdirAll(dir, 0755)
		if err != nil {
			return err
		}
	}

	// Create a self-signed certificate for initialization
	tempDir, err := os.MkdirTemp("", "jks-init")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tempDir)

	keyPath := filepath.Join(tempDir, "temp.key")
	certPath := filepath.Join(tempDir, "temp.crt")

	// Generate a self-signed certificate
	err = generateTestCertificate(certPath, keyPath)
	if err != nil {
		return err
	}

	// Create the keystore
	createCmd := exec.Command(
		keytoolPath,
		"-genkeypair",
		"-keystore", filePath,
		"-storepass", password,
		"-keyalg", "RSA",
		"-keysize", "2048",
		"-dname", "CN=JKS Initialization, O=Trust Store Manager, C=US",
		"-alias", "init",
		"-validity", "365",
	)

	return createCmd.Run()
}
