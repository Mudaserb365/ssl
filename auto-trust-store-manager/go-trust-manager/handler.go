package main

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

// processTrustStore processes a single trust store file
func processTrustStore(filePath string, config Config) error {
	fileType, err := detectFileType(filePath)
	if err != nil {
		return fmt.Errorf("error detecting file type: %v", err)
	}

	logInfo(fmt.Sprintf("Processing trust store: %s (Type: %s)", filePath, fileType))

	// If baseline URL is provided, compare first
	if config.BaselineURL != "" {
		err := compareTrustStores(filePath, config.BaselineURL, fileType, config)
		if err != nil {
			logWarning(fmt.Sprintf("Error comparing trust stores: %v", err))
		}

		// If in compare-only mode, don't modify the trust store
		if config.CompareOnly {
			return nil
		}
	}

	// Handle different trust store types
	switch fileType {
	case FileTypeJKS:
		return handleJKS(filePath, config)
	case FileTypePKCS12:
		return handlePKCS12(filePath, config)
	case FileTypePEM:
		return handlePEM(filePath, config)
	case FileTypeUnknown:
		logWarning(fmt.Sprintf("Unknown file type for %s, skipping", filePath))
		return nil
	}

	return nil
}

// createBackup creates a backup of a file
func createBackup(filePath string, config Config) (string, error) {
	if !config.BackupEnabled {
		logDebug(config, fmt.Sprintf("Backup disabled, skipping backup creation for %s", filePath))
		return "", nil
	}

	// Create a timestamped backup filename
	timestamp := time.Now().Format("20060102_150405")
	backupPath := fmt.Sprintf("%s.bak.%s", filePath, timestamp)

	// Copy the file
	input, err := ioutil.ReadFile(filePath)
	if err != nil {
		return "", err
	}

	err = ioutil.WriteFile(backupPath, input, 0644)
	if err != nil {
		return "", err
	}

	logDebug(config, fmt.Sprintf("Created backup: %s", backupPath))
	return backupPath, nil
}

// handleJKS processes a JKS trust store
func handleJKS(filePath string, config Config) error {
	logInfo(fmt.Sprintf("Processing JKS trust store: %s", filePath))

	// Check if keytool is available
	keytoolPath, err := findKeytool()
	if err != nil {
		return fmt.Errorf("keytool not found: %v", err)
	}

	// Try each password
	success := false
	var successPassword string
	alias := fmt.Sprintf("trust-store-scanner-%d", time.Now().Unix())

	for _, password := range config.Passwords {
		logDebug(config, fmt.Sprintf("Trying password: %s", password))

		// Test if the password works
		cmd := exec.Command(keytoolPath, "-list", "-keystore", filePath, "-storepass", password)
		err := cmd.Run()
		if err == nil {
			logSuccess(fmt.Sprintf("Successfully accessed JKS with password: %s", password))
			successPassword = password
			success = true
			break
		}
	}

	if !success {
		return fmt.Errorf("could not access JKS file with any of the provided passwords")
	}

	// Create backup
	backupPath, err := createBackup(filePath, config)
	if err != nil {
		return fmt.Errorf("failed to create backup: %v", err)
	}

	// Import the certificate
	cmd := exec.Command(
		keytoolPath,
		"-importcert",
		"-noprompt",
		"-keystore", filePath,
		"-storepass", successPassword,
		"-alias", alias,
		"-file", config.CertificatePath,
	)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	err = cmd.Run()
	if err != nil {
		logError(fmt.Sprintf("Failed to import certificate to %s: %v, %s", filePath, err, stderr.String()))

		// Restore from backup if available
		if backupPath != "" {
			restoreFromBackup(backupPath, filePath)
		}

		return fmt.Errorf("failed to import certificate")
	}

	// Verify the import
	verifyCmd := exec.Command(
		keytoolPath,
		"-list",
		"-keystore", filePath,
		"-storepass", successPassword,
		"-alias", alias,
	)

	err = verifyCmd.Run()
	if err != nil {
		logError(fmt.Sprintf("Failed to verify certificate import to %s", filePath))

		// Restore from backup if available
		if backupPath != "" {
			restoreFromBackup(backupPath, filePath)
		}

		return fmt.Errorf("failed to verify certificate import")
	}

	logSuccess(fmt.Sprintf("Successfully imported certificate to %s with alias %s", filePath, alias))

	// Log command to remove the test certificate if needed
	logInfo(fmt.Sprintf("To remove the test certificate: keytool -delete -keystore \"%s\" -storepass \"%s\" -alias \"%s\"",
		filePath, successPassword, alias))

	return nil
}

// handlePKCS12 processes a PKCS12 trust store
func handlePKCS12(filePath string, config Config) error {
	logInfo(fmt.Sprintf("Processing PKCS12 trust store: %s", filePath))

	// Try each password
	success := false
	var successPassword string
	tempPem := filepath.Join(os.TempDir(), fmt.Sprintf("pkcs12_extract_%d.pem", time.Now().Unix()))

	for _, password := range config.Passwords {
		logDebug(config, fmt.Sprintf("Trying password: %s", password))

		// Test if the password works
		cmd := exec.Command(
			"openssl", "pkcs12",
			"-in", filePath,
			"-nokeys",
			"-passin", fmt.Sprintf("pass:%s", password),
			"-out", tempPem,
		)

		err := cmd.Run()
		if err == nil {
			logSuccess(fmt.Sprintf("Successfully accessed PKCS12 with password: %s", password))
			successPassword = password
			success = true
			break
		}
	}

	if !success {
		return fmt.Errorf("could not access PKCS12 file with any of the provided passwords")
	}

	// Create backup
	backupPath, err := createBackup(filePath, config)
	if err != nil {
		return fmt.Errorf("failed to create backup: %v", err)
	}

	// Extract certificates to PEM
	extractCmd := exec.Command(
		"openssl", "pkcs12",
		"-in", filePath,
		"-nokeys",
		"-passin", fmt.Sprintf("pass:%s", successPassword),
		"-out", tempPem,
	)

	err = extractCmd.Run()
	if err != nil {
		return fmt.Errorf("failed to extract certificates from PKCS12: %v", err)
	}

	// Append new certificate to temp PEM
	certData, err := os.ReadFile(config.CertificatePath)
	if err != nil {
		return fmt.Errorf("failed to read certificate file: %v", err)
	}

	pemData, err := os.ReadFile(tempPem)
	if err != nil {
		return fmt.Errorf("failed to read extracted PEM file: %v", err)
	}

	// Append certificate to PEM
	updatedPem := append(pemData, certData...)
	err = os.WriteFile(tempPem, updatedPem, 0644)
	if err != nil {
		return fmt.Errorf("failed to write updated PEM file: %v", err)
	}

	// Convert back to PKCS12
	convertCmd := exec.Command(
		"openssl", "pkcs12",
		"-export",
		"-in", tempPem,
		"-nokeys",
		"-passout", fmt.Sprintf("pass:%s", successPassword),
		"-out", filePath,
	)

	err = convertCmd.Run()
	if err != nil {
		logError(fmt.Sprintf("Failed to update PKCS12 file %s: %v", filePath, err))

		// Restore from backup if available
		if backupPath != "" {
			restoreFromBackup(backupPath, filePath)
		}

		return fmt.Errorf("failed to update PKCS12 file")
	}

	// Clean up
	os.Remove(tempPem)

	logSuccess(fmt.Sprintf("Successfully updated PKCS12 file %s", filePath))

	return nil
}

// handlePEM processes a PEM trust store
func handlePEM(filePath string, config Config) error {
	logInfo(fmt.Sprintf("Processing PEM trust store: %s", filePath))

	// Check if file is readable
	_, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("PEM file %s is not accessible: %v", filePath, err)
	}

	// Create backup
	backupPath, err := createBackup(filePath, config)
	if err != nil {
		return fmt.Errorf("failed to create backup: %v", err)
	}

	// Read certificate file
	certData, err := os.ReadFile(config.CertificatePath)
	if err != nil {
		return fmt.Errorf("failed to read certificate file: %v", err)
	}

	// Open the trust store file for appending
	file, err := os.OpenFile(filePath, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to open PEM file for writing: %v", err)
	}
	defer file.Close()

	// Append a newline before certificate if needed
	file.Write([]byte("\n"))

	// Append certificate
	_, err = file.Write(certData)
	if err != nil {
		logError(fmt.Sprintf("Failed to append certificate to PEM file %s: %v", filePath, err))

		// Restore from backup if available
		if backupPath != "" {
			restoreFromBackup(backupPath, filePath)
		}

		return fmt.Errorf("failed to append certificate to PEM file")
	}

	logSuccess(fmt.Sprintf("Successfully appended certificate to PEM file %s", filePath))

	return nil
}

// compareTrustStores compares a trust store with a baseline
func compareTrustStores(filePath, baselinePath string, fileType FileType, config Config) error {
	logInfo(fmt.Sprintf("Comparing trust store: %s with baseline", filePath))

	// Implementation of trust store comparison
	// This is a stub and should be expanded based on specific requirements

	// For complete implementation, we would:
	// 1. Extract all certificates from both trust stores to temp PEM files
	// 2. Compute fingerprints of each certificate
	// 3. Compare fingerprints to find missing certificates
	// 4. Report on differences

	// For now, we'll just acknowledge the comparison
	logInfo("Trust store comparison not fully implemented in this version")

	return nil
}

// restartAffectedServices restarts services that might be using the trust stores
func restartAffectedServices(config Config) error {
	logInfo("Checking for services that need to be restarted")

	// Only Linux systems support service restart through systemctl
	if runtime.GOOS != "linux" {
		logWarning("Service restart only supported on Linux")
		return nil
	}

	// Common services that use trust stores
	services := []string{
		"tomcat",
		"apache2",
		"httpd",
		"nginx",
		"wildfly",
		"jboss",
	}

	for _, service := range services {
		// Check if service is active
		checkCmd := exec.Command("systemctl", "is-active", "--quiet", service)
		err := checkCmd.Run()
		if err == nil {
			logInfo(fmt.Sprintf("Restarting service: %s", service))

			// Restart the service
			restartCmd := exec.Command("systemctl", "restart", service)
			err := restartCmd.Run()
			if err == nil {
				logSuccess(fmt.Sprintf("Successfully restarted %s", service))
			} else {
				logError(fmt.Sprintf("Failed to restart %s: %v", service, err))
			}
		}
	}

	return nil
}

// scanKubernetes scans Kubernetes ConfigMaps and Secrets for trust stores
func scanKubernetes(config Config) error {
	logInfo("Scanning Kubernetes resources for trust stores")

	// Check if kubectl is available
	_, err := exec.LookPath("kubectl")
	if err != nil {
		return fmt.Errorf("kubectl command not found, cannot scan Kubernetes resources")
	}

	// This is a placeholder for Kubernetes scanning logic
	// Implementing the full Kubernetes scanning would require:
	// 1. Getting all ConfigMaps/Secrets with kubectl
	// 2. Filtering ones that have certificate files
	// 3. Extracting and processing them
	// 4. Updating the resources

	logInfo("Kubernetes scanning not fully implemented in this version")

	return nil
}

// scanDocker scans Docker containers for trust stores
func scanDocker(config Config) error {
	logInfo("Scanning Docker containers for trust stores")

	// Check if docker is available
	_, err := exec.LookPath("docker")
	if err != nil {
		return fmt.Errorf("docker command not found, cannot scan Docker containers")
	}

	// This is a placeholder for Docker scanning logic
	// Implementing the full Docker scanning would require:
	// 1. Listing all running containers
	// 2. Finding trust stores in each container
	// 3. Copying them out, processing them, and copying back
	// 4. Optionally restarting containers

	logInfo("Docker scanning not fully implemented in this version")

	return nil
}

// findKeytool searches for the keytool executable using targeted path checks
func findKeytool() (string, error) {
	// First check if keytool is in PATH (most efficient)
	keytoolPath, err := exec.LookPath("keytool")
	if err == nil {
		logSuccess(fmt.Sprintf("Found keytool in PATH: %s", keytoolPath))
		return keytoolPath, nil
	}

	// Check JAVA_HOME environment variable (second most efficient)
	javaHome := os.Getenv("JAVA_HOME")
	if javaHome != "" {
		// Try common bin locations relative to JAVA_HOME
		locations := []string{
			filepath.Join(javaHome, "bin", "keytool"),
			filepath.Join(javaHome, "jre", "bin", "keytool"),
		}

		// Add .exe extension for Windows
		if runtime.GOOS == "windows" {
			locations = append(
				locations,
				filepath.Join(javaHome, "bin", "keytool.exe"),
				filepath.Join(javaHome, "jre", "bin", "keytool.exe"),
			)
		}

		// Check each potential location
		for _, location := range locations {
			if fileExists(location) && isExecutable(location) {
				logSuccess(fmt.Sprintf("Found keytool via JAVA_HOME: %s", location))
				return location, nil
			}
		}
	}

	// Targeted search in OS-specific locations
	var searchPaths []string

	switch runtime.GOOS {
	case "windows":
		// Windows: Check Program Files with specific JDK/JRE version patterns
		programFiles := []string{
			os.Getenv("ProgramFiles"),
			os.Getenv("ProgramFiles(x86)"),
			"C:\\Program Files",
			"C:\\Program Files (x86)",
		}

		// Common Java installation patterns on Windows
		javaPatterns := []string{
			"Java\\jdk*\\bin\\keytool.exe",
			"Java\\jre*\\bin\\keytool.exe",
			"OpenJDK\\*\\bin\\keytool.exe",
			"AdoptOpenJDK\\*\\bin\\keytool.exe",
			"Zulu\\*\\bin\\keytool.exe",
			"Amazon Corretto\\*\\bin\\keytool.exe",
		}

		// Combine paths with patterns
		for _, dir := range programFiles {
			if dir == "" {
				continue
			}
			for _, pattern := range javaPatterns {
				searchPaths = append(searchPaths, filepath.Join(dir, pattern))
			}
		}

	case "darwin":
		// macOS: Check specific JDK installation locations
		searchPaths = []string{
			"/Library/Java/JavaVirtualMachines/*/Contents/Home/bin/keytool",
			"/System/Library/Java/JavaVirtualMachines/*/Contents/Home/bin/keytool",
			"/usr/local/opt/openjdk*/bin/keytool",
			"/usr/bin/keytool",
			"/usr/local/bin/keytool",
		}

	case "linux":
		// Linux: Check common JDK installation locations
		searchPaths = []string{
			"/usr/lib/jvm/*/bin/keytool",
			"/usr/lib/jvm/*/jre/bin/keytool",
			"/usr/java/*/bin/keytool",
			"/usr/java/*/jre/bin/keytool",
			"/usr/local/java/*/bin/keytool",
			"/opt/java/*/bin/keytool",
			"/opt/jdk/*/bin/keytool",
			"/opt/openjdk/*/bin/keytool",
			"/usr/bin/keytool",
			"/usr/local/bin/keytool",
		}
	}

	// Check each path specifically, using a glob pattern for efficiency
	for _, pathPattern := range searchPaths {
		matches, err := filepath.Glob(pathPattern)
		if err != nil {
			continue // Skip invalid patterns
		}

		for _, match := range matches {
			if fileExists(match) && isExecutable(match) {
				logSuccess(fmt.Sprintf("Found keytool: %s", match))
				return match, nil
			}
		}
	}

	// Check user home directory for SDK installations (like SDKMAN)
	home, err := os.UserHomeDir()
	if err == nil {
		var sdkPaths []string

		switch runtime.GOOS {
		case "windows":
			sdkPaths = []string{
				filepath.Join(home, ".sdkman", "candidates", "java", "*", "bin", "keytool.exe"),
			}
		default:
			sdkPaths = []string{
				filepath.Join(home, ".sdkman", "candidates", "java", "*", "bin", "keytool"),
				filepath.Join(home, ".jabba", "jdk", "*", "bin", "keytool"),
			}
		}

		for _, pathPattern := range sdkPaths {
			matches, err := filepath.Glob(pathPattern)
			if err != nil {
				continue
			}

			for _, match := range matches {
				if fileExists(match) && isExecutable(match) {
					logSuccess(fmt.Sprintf("Found keytool in user SDK: %s", match))
					return match, nil
				}
			}
		}
	}

	return "", fmt.Errorf("keytool not found in any standard location")
}

// isExecutable checks if a file is executable
func isExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}

	// For Windows, just check if the file exists
	if runtime.GOOS == "windows" {
		return true
	}

	// For Unix-like systems, check executable permission
	return info.Mode()&0111 != 0
}

// restoreFromBackup restores a file from backup
func restoreFromBackup(backupPath, originalPath string) error {
	data, err := ioutil.ReadFile(backupPath)
	if err != nil {
		return err
	}

	err = ioutil.WriteFile(originalPath, data, 0644)
	if err != nil {
		return err
	}

	logInfo(fmt.Sprintf("Restored from backup: %s", backupPath))
	return nil
}

// checkDependencies verifies that required tools are available
func checkDependencies(config Config) error {
	// Basic dependencies
	basicDeps := []string{"openssl", "find", "grep"}
	missing := false

	for _, cmd := range basicDeps {
		_, err := exec.LookPath(cmd)
		if err != nil {
			logError(fmt.Sprintf("Required command not found: %s", cmd))
			missing = true
		}
	}

	// Check for keytool if JKS files are likely to be processed
	_, err := findKeytool()
	if err != nil {
		logWarning("Keytool not found. Java KeyStore (JKS) files cannot be processed.")
		// We don't set missing to true here since we can still process other types
	}

	if missing {
		return fmt.Errorf("please install missing dependencies and try again")
	}

	return nil
}
