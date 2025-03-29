package main

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// Default paths for certificates
const (
	defaultCertPath = "test-cert.pem"
	defaultKeyPath  = "test-key.pem"
)

// validateCertificate ensures a valid certificate is available
func validateCertificate(config *Config) error {
	// If no certificate path is provided, generate a test certificate
	if config.CertificatePath == "" {
		tempDir, err := os.MkdirTemp("", "trust-store-manager")
		if err != nil {
			return fmt.Errorf("failed to create temp directory: %v", err)
		}

		config.CertificatePath = filepath.Join(tempDir, defaultCertPath)
		keyPath := filepath.Join(tempDir, defaultKeyPath)

		err = generateTestCertificate(config.CertificatePath, keyPath)
		if err != nil {
			return fmt.Errorf("failed to generate test certificate: %v", err)
		}

		logInfo(fmt.Sprintf("Generated test certificate at %s", config.CertificatePath))
	} else {
		// Check if provided certificate exists
		_, err := os.Stat(config.CertificatePath)
		if err != nil {
			return fmt.Errorf("certificate file does not exist: %s", config.CertificatePath)
		}

		// Validate certificate format
		certData, err := os.ReadFile(config.CertificatePath)
		if err != nil {
			return fmt.Errorf("failed to read certificate file: %v", err)
		}

		block, _ := pem.Decode(certData)
		if block == nil || block.Type != "CERTIFICATE" {
			return fmt.Errorf("invalid certificate format: %s", config.CertificatePath)
		}

		_, err = x509.ParseCertificate(block.Bytes)
		if err != nil {
			return fmt.Errorf("failed to parse certificate: %v", err)
		}
	}

	return nil
}

// generateTestCertificate creates a self-signed test certificate
func generateTestCertificate(certPath, keyPath string) error {
	// Try using openssl if available (for compatibility with more formats)
	if opensslAvailable() {
		return generateCertificateWithOpenSSL(certPath, keyPath)
	}

	// Fallback to native Go implementation
	return generateCertificateNative(certPath, keyPath)
}

// opensslAvailable checks if openssl command is available
func opensslAvailable() bool {
	_, err := exec.LookPath("openssl")
	return err == nil
}

// generateCertificateWithOpenSSL creates a certificate using the openssl command
func generateCertificateWithOpenSSL(certPath, keyPath string) error {
	// Create a command to generate a self-signed certificate
	cmd := exec.Command(
		"openssl", "req", "-x509", "-newkey", "rsa:4096",
		"-keyout", keyPath,
		"-out", certPath,
		"-days", "365",
		"-nodes",
		"-subj", "/CN=Test Certificate/O=Trust Store Scanner/C=US",
	)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("openssl error: %v, %s", err, stderr.String())
	}

	return nil
}

// generateCertificateNative creates a certificate using Go's crypto package
func generateCertificateNative(certPath, keyPath string) error {
	// Generate a new private key
	privateKey, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		return fmt.Errorf("failed to generate private key: %v", err)
	}

	// Create a certificate template
	serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return fmt.Errorf("failed to generate serial number: %v", err)
	}

	now := time.Now()
	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			CommonName:   "Test Certificate",
			Organization: []string{"Trust Store Scanner"},
			Country:      []string{"US"},
		},
		NotBefore:             now,
		NotAfter:              now.Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
		BasicConstraintsValid: true,
		IsCA:                  true,
	}

	// Create the self-signed certificate
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &privateKey.PublicKey, privateKey)
	if err != nil {
		return fmt.Errorf("failed to create certificate: %v", err)
	}

	// Encode and save the certificate
	certOut, err := os.Create(certPath)
	if err != nil {
		return fmt.Errorf("failed to open certificate file for writing: %v", err)
	}
	defer certOut.Close()

	err = pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	if err != nil {
		return fmt.Errorf("failed to encode certificate to PEM: %v", err)
	}

	// Encode and save the private key
	keyOut, err := os.Create(keyPath)
	if err != nil {
		return fmt.Errorf("failed to open key file for writing: %v", err)
	}
	defer keyOut.Close()

	keyBlock := &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privateKey),
	}

	err = pem.Encode(keyOut, keyBlock)
	if err != nil {
		return fmt.Errorf("failed to encode private key to PEM: %v", err)
	}

	return nil
}

// downloadBaselineStore downloads a trust store from a URL
func downloadBaselineStore(config Config) error {
	baselineStorePath := filepath.Join(os.TempDir(), fmt.Sprintf("baseline_trust_store_%d", time.Now().Unix()))

	logInfo(fmt.Sprintf("Downloading baseline trust store from %s", config.BaselineURL))

	// Create an HTTP client with a timeout
	client := &http.Client{
		Timeout: 30 * time.Second,
	}

	// Make the HTTP request
	resp, err := client.Get(config.BaselineURL)
	if err != nil {
		return fmt.Errorf("failed to download baseline store: %v", err)
	}
	defer resp.Body.Close()

	// Check for successful status code
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to download baseline store: HTTP status %d", resp.StatusCode)
	}

	// Create the output file
	out, err := os.Create(baselineStorePath)
	if err != nil {
		return fmt.Errorf("failed to create baseline store file: %v", err)
	}
	defer out.Close()

	// Copy the response body to the file
	_, err = io.Copy(out, resp.Body)
	if err != nil {
		return fmt.Errorf("failed to write baseline store file: %v", err)
	}

	logSuccess(fmt.Sprintf("Successfully downloaded baseline trust store to %s", baselineStorePath))

	// Update the config with the downloaded file path
	config.BaselineURL = baselineStorePath

	return nil
}
