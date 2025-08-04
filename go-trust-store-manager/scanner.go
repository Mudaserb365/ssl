package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// scanDirectory searches for trust stores in a directory
func scanDirectory(config *Config) error {
	logInfo(fmt.Sprintf("Scanning directory: %s", config.TargetDir))

	// Get absolute path for consistent handling
	absPath, err := filepath.Abs(config.TargetDir)
	if err != nil {
		return fmt.Errorf("failed to get absolute path for %s: %v", config.TargetDir, err)
	}

	// Find trust stores
	trustStores, err := findTrustStores(absPath)
	if err != nil {
		return fmt.Errorf("error finding trust stores: %v", err)
	}

	if len(trustStores) == 0 {
		logWarning("No trust stores found in directory")
		return nil
	}

	logInfo(fmt.Sprintf("Found %d potential trust stores", len(trustStores)))

	// Process each trust store
	for _, file := range trustStores {
		err := processTrustStore(file, config)
		if err != nil {
			logError(fmt.Sprintf("Error processing trust store %s: %v", file, err))
		}
	}

	return nil
}

// findTrustStores searches for trust stores in a directory
func findTrustStores(dirPath string) ([]string, error) {
	var trustStores []string

	// Find files by extension
	err := filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip directories and hidden files
		if info.IsDir() {
			if strings.HasPrefix(info.Name(), ".") ||
				strings.HasPrefix(info.Name(), "node_modules") {
				return filepath.SkipDir
			}
			return nil
		}

		// Check if file is a potential trust store by extension
		ext := strings.ToLower(filepath.Ext(path))
		name := strings.ToLower(info.Name())

		if ext == ".jks" || ext == ".keystore" || ext == ".truststore" ||
			ext == ".p12" || ext == ".pfx" ||
			ext == ".pem" || ext == ".crt" || ext == ".cer" || ext == ".cert" ||
			// Also check for files named cacerts (Java default)
			name == "cacerts" {
			trustStores = append(trustStores, path)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Find additional trust stores from configuration files
	configPaths, err := extractConfigPaths(dirPath)
	if err != nil {
		return nil, err
	}

	// Add config paths to the list
	for _, path := range configPaths {
		if fileExists(path) {
			trustStores = append(trustStores, path)
		}
	}

	// Remove duplicates
	return removeDuplicates(trustStores), nil
}

// extractConfigPaths finds trust store paths in configuration files
func extractConfigPaths(dirPath string) ([]string, error) {
	var paths []string

	// Java properties files
	javaPropsPaths, err := findJavaTrustStoreProps(dirPath)
	if err != nil {
		return nil, err
	}
	paths = append(paths, javaPropsPaths...)

	// Environment files
	envFilePaths, err := findEnvFileTrustStores(dirPath)
	if err != nil {
		return nil, err
	}
	paths = append(paths, envFilePaths...)

	// Node.js files
	nodejsPaths, err := findNodejsTrustStores(dirPath)
	if err != nil {
		return nil, err
	}
	paths = append(paths, nodejsPaths...)

	// Web server config files
	webServerPaths, err := findWebServerTrustStores(dirPath)
	if err != nil {
		return nil, err
	}
	paths = append(paths, webServerPaths...)

	return paths, nil
}

// findJavaTrustStoreProps extracts trust store paths from Java properties files
func findJavaTrustStoreProps(dirPath string) ([]string, error) {
	var paths []string

	// Patterns to match in property files
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)(trustStore|trust-store|truststore).*=(.+)`),
		regexp.MustCompile(`(?i)(javax\.net\.ssl\.trustStore).*=(.+)`),
	}

	// Find property files
	propFiles, err := findFilesByPattern(dirPath, []string{".properties", ".conf", ".xml", ".yaml", ".yml"})
	if err != nil {
		return nil, err
	}

	// Search each file for trust store properties
	for _, file := range propFiles {
		content, err := os.ReadFile(file)
		if err != nil {
			continue
		}

		lines := strings.Split(string(content), "\n")
		for _, line := range lines {
			for _, pattern := range patterns {
				matches := pattern.FindStringSubmatch(line)
				if len(matches) > 2 {
					path := strings.TrimSpace(matches[2])
					// Handle relative paths
					if !filepath.IsAbs(path) {
						path = filepath.Join(filepath.Dir(file), path)
					}
					paths = append(paths, path)
				}
			}
		}
	}

	return paths, nil
}

// findEnvFileTrustStores extracts trust store paths from environment files
func findEnvFileTrustStores(dirPath string) ([]string, error) {
	var paths []string

	// Pattern to match in .env files
	pattern := regexp.MustCompile(`(?i)(TRUSTSTORE|TRUST_STORE).*=(.+)`)

	// Find .env files
	envFiles, err := findFilesByPattern(dirPath, []string{".env"})
	if err != nil {
		return nil, err
	}

	// Search each file for trust store environment variables
	for _, file := range envFiles {
		content, err := os.ReadFile(file)
		if err != nil {
			continue
		}

		lines := strings.Split(string(content), "\n")
		for _, line := range lines {
			matches := pattern.FindStringSubmatch(line)
			if len(matches) > 2 {
				path := strings.TrimSpace(matches[2])
				// Handle relative paths
				if !filepath.IsAbs(path) {
					path = filepath.Join(filepath.Dir(file), path)
				}
				paths = append(paths, path)
			}
		}
	}

	return paths, nil
}

// findNodejsTrustStores extracts trust store paths from Node.js files
func findNodejsTrustStores(dirPath string) ([]string, error) {
	var paths []string

	// Pattern to match in Node.js files
	pattern := regexp.MustCompile(`(?i)NODE_EXTRA_CA_CERTS.*=(.+)`)

	// Find Node.js files
	nodeFiles, err := findFilesByPattern(dirPath, []string{".js", ".json"})
	if err != nil {
		return nil, err
	}

	// Search each file for NODE_EXTRA_CA_CERTS variables
	for _, file := range nodeFiles {
		content, err := os.ReadFile(file)
		if err != nil {
			continue
		}

		lines := strings.Split(string(content), "\n")
		for _, line := range lines {
			matches := pattern.FindStringSubmatch(line)
			if len(matches) > 1 {
				path := strings.TrimSpace(matches[1])
				// Remove quotes
				path = strings.Trim(path, `'"`)
				// Handle relative paths
				if !filepath.IsAbs(path) {
					path = filepath.Join(filepath.Dir(file), path)
				}
				paths = append(paths, path)
			}
		}
	}

	return paths, nil
}

// findWebServerTrustStores extracts trust store paths from web server config files
func findWebServerTrustStores(dirPath string) ([]string, error) {
	var paths []string

	// Patterns to match in web server config files
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)ssl_trusted_certificate[[:space:]]+([^;]+)`),
		regexp.MustCompile(`(?i)SSLCACertificateFile[[:space:]]+(.+)`),
	}

	// Find web server config files
	configFiles, err := findFilesByPattern(dirPath, []string{".conf"})
	if err != nil {
		return nil, err
	}

	// Search each file for trust store paths
	for _, file := range configFiles {
		content, err := os.ReadFile(file)
		if err != nil {
			continue
		}

		lines := strings.Split(string(content), "\n")
		for _, line := range lines {
			for _, pattern := range patterns {
				matches := pattern.FindStringSubmatch(line)
				if len(matches) > 1 {
					path := strings.TrimSpace(matches[1])
					// Remove quotes
					path = strings.Trim(path, `'"`)
					// Handle relative paths
					if !filepath.IsAbs(path) {
						path = filepath.Join(filepath.Dir(file), path)
					}
					paths = append(paths, path)
				}
			}
		}
	}

	return paths, nil
}

// findFilesByPattern finds files with specific extensions in a directory tree
func findFilesByPattern(dirPath string, extensions []string) ([]string, error) {
	var matches []string

	err := filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip directories and hidden files
		if info.IsDir() {
			if strings.HasPrefix(info.Name(), ".") ||
				strings.HasPrefix(info.Name(), "node_modules") {
				return filepath.SkipDir
			}
			return nil
		}

		// Check file extensions
		for _, ext := range extensions {
			if strings.HasSuffix(strings.ToLower(info.Name()), ext) {
				matches = append(matches, path)
				break
			}
		}

		return nil
	})

	return matches, err
}

// detectFileType determines the type of a trust store file
func detectFileType(filePath string) (FileType, error) {
	// First check by extension
	ext := strings.ToLower(filepath.Ext(filePath))

	switch ext {
	case ".jks", ".keystore", ".truststore":
		return FileTypeJKS, nil
	case ".p12", ".pfx":
		return FileTypePKCS12, nil
	case ".pem", ".crt", ".cer", ".cert":
		return FileTypePEM, nil
	}

	// If extension doesn't give us a clue, check file content
	file, err := os.Open(filePath)
	if err != nil {
		return FileTypeUnknown, err
	}
	defer file.Close()

	// Read first few bytes to determine file type
	header := make([]byte, 4)
	_, err = file.Read(header)
	if err != nil {
		return FileTypeUnknown, err
	}

	// Reset file pointer
	_, err = file.Seek(0, 0)
	if err != nil {
		return FileTypeUnknown, err
	}

	// Check for PEM format (ASCII text starting with "----")
	pemHeader := []byte("----")
	if string(header) == string(pemHeader) {
		// Read more to confirm it's a PEM certificate
		content, err := io.ReadAll(file)
		if err != nil {
			return FileTypeUnknown, err
		}
		if strings.Contains(string(content), "BEGIN CERTIFICATE") {
			return FileTypePEM, nil
		}
	}

	// Check for JKS magic header (0xFEEDFEED)
	jksMagic := []byte{0xFE, 0xED, 0xFE, 0xED}
	if string(header) == string(jksMagic) {
		return FileTypeJKS, nil
	}

	// For PKCS12, we need to try with openssl
	if opensslAvailable() {
		isP12, _ := isPKCS12WithOpenSSL(filePath)
		if isP12 {
			return FileTypePKCS12, nil
		}
	}

	return FileTypeUnknown, nil
}

// isPKCS12WithOpenSSL checks if a file is a PKCS12 store using openssl
func isPKCS12WithOpenSSL(filePath string) (bool, error) {
	cmd := exec.Command("openssl", "pkcs12", "-info", "-in", filePath, "-noout", "-password", "pass:")
	err := cmd.Run()
	// If the command succeeds (or fails with exit code 1 but was able to parse as PKCS12),
	// it's likely a PKCS12 file
	return err == nil || cmd.ProcessState.ExitCode() == 1, nil
}

// Helper functions

// fileExists checks if a file exists
func fileExists(filePath string) bool {
	info, err := os.Stat(filePath)
	if os.IsNotExist(err) {
		return false
	}
	return !info.IsDir()
}

// removeDuplicates removes duplicate entries from a string slice
func removeDuplicates(strSlice []string) []string {
	keys := make(map[string]bool)
	list := []string{}

	for _, entry := range strSlice {
		if _, value := keys[entry]; !value {
			keys[entry] = true
			list = append(list, entry)
		}
	}

	return list
}
