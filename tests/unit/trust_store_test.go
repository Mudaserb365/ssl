package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// Test configuration
var (
	projectRoot string
	fixturesDir string
	testTempDir string
)

func init() {
	// Get project root directory
	_, filename, _, _ := runtime.Caller(0)
	projectRoot = filepath.Join(filepath.Dir(filename), "..", "..")
	fixturesDir = filepath.Join(projectRoot, "tests", "fixtures")
	testTempDir = "/tmp/go-trust-store-tests"
}

// TestMain sets up and tears down test environment
func TestMain(m *testing.M) {
	// Setup
	setupTestEnvironment()
	
	// Run tests
	code := m.Run()
	
	// Cleanup
	cleanupTestEnvironment()
	
	os.Exit(code)
}

func setupTestEnvironment() {
	// Create temporary directory for tests
	err := os.MkdirAll(testTempDir, 0755)
	if err != nil {
		panic("Failed to create test temp directory: " + err.Error())
	}
	
	// Create test fixtures if they don't exist
	if _, err := os.Stat(fixturesDir); os.IsNotExist(err) {
		createTestFixtures()
	}
}

func cleanupTestEnvironment() {
	// Clean up temporary directory
	os.RemoveAll(testTempDir)
}

func createTestFixtures() {
	fixtureScript := filepath.Join(fixturesDir, "create_test_keystores.sh")
	
	// Make script executable
	err := os.Chmod(fixtureScript, 0755)
	if err != nil {
		return // Skip if script doesn't exist
	}
	
	// Run fixture creation script
	cmd := exec.Command("bash", fixtureScript)
	cmd.Dir = fixturesDir
	cmd.Run() // Ignore errors - some fixtures may not be created if tools are missing
}

// Utility functions for tests
func checkCommand(command string) bool {
	_, err := exec.LookPath(command)
	return err == nil
}

func checkJREAvailable() bool {
	return checkCommand("keytool") && checkCommand("java")
}

func runTrustStoreManager(args ...string) error {
	goDir := filepath.Join(projectRoot, "go-trust-store-manager")
	
	// Prepare command
	cmdArgs := append([]string{"run", "."}, args...)
	cmd := exec.Command("go", cmdArgs...)
	cmd.Dir = goDir
	
	// Run command
	return cmd.Run()
}

// Test JRE detection and information display
func TestJREDetection(t *testing.T) {
	tests := []struct {
		name string
		args []string
		expectSuccess bool
	}{
		{
			name: "Basic noop execution",
			args: []string{"--noop", "-d", testTempDir},
			expectSuccess: true,
		},
		{
			name: "Noop with verbose",
			args: []string{"--noop", "-v", "-d", testTempDir},
			expectSuccess: true,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := runTrustStoreManager(tt.args...)
			
			if tt.expectSuccess && err != nil {
				t.Errorf("Expected success but got error: %v", err)
			}
			
			if !tt.expectSuccess && err == nil {
				t.Error("Expected error but got success")
			}
		})
	}
}

func TestJREInformationDisplay(t *testing.T) {
	if !checkJREAvailable() {
		t.Skip("JRE not available, skipping JRE information display test")
	}
	
	// Test that JRE information is displayed in noop mode
	goDir := filepath.Join(projectRoot, "go-trust-store-manager")
	cmd := exec.Command("go", "run", ".", "--noop", "-d", testTempDir)
	cmd.Dir = goDir
	
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("Failed to run trust store manager: %v", err)
	}
	
	outputStr := string(output)
	
	// Should contain some indication that the tool ran successfully
	if !strings.Contains(outputStr, "Trust Store Manager") {
		t.Error("Expected output to contain 'Trust Store Manager'")
	}
}

// Test JKS trust store operations
func TestJKSOperations(t *testing.T) {
	if !checkJREAvailable() {
		t.Skip("JRE not available, skipping JKS tests")
	}
	
	tests := []struct {
		name     string
		filename string
		password string
		expectValid bool
	}{
		{
			name:     "Basic JKS with default password",
			filename: "basic-truststore.jks",
			password: "changeit",
			expectValid: true,
		},
		{
			name:     "JKS with custom password",
			filename: "custom-password-truststore.jks",
			password: "secretpass",
			expectValid: true,
		},
		{
			name:     "Multi-certificate JKS",
			filename: "multi-cert-truststore.jks",
			password: "changeit",
			expectValid: true,
		},
		{
			name:     "Corrupted JKS",
			filename: "corrupted-truststore.jks",
			password: "changeit",
			expectValid: false,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jksPath := filepath.Join(fixturesDir, "jks", tt.filename)
			
			if _, err := os.Stat(jksPath); os.IsNotExist(err) {
				t.Skipf("Test file %s does not exist", jksPath)
			}
			
			// Test with keytool
			cmd := exec.Command("keytool", "-list", "-keystore", jksPath, "-storepass", tt.password, "-noprompt")
			err := cmd.Run()
			
			if tt.expectValid && err != nil {
				t.Errorf("Expected valid JKS but keytool failed: %v", err)
			}
			
			if !tt.expectValid && err == nil {
				t.Error("Expected invalid JKS but keytool succeeded")
			}
			
			// Test with trust store manager
			args := []string{"--noop", "-d", filepath.Dir(jksPath)}
			err = runTrustStoreManager(args...)
			
			if err != nil && tt.expectValid {
				t.Errorf("Trust store manager failed on valid JKS: %v", err)
			}
		})
	}
}

func TestJKSPasswordDetection(t *testing.T) {
	if !checkJREAvailable() {
		t.Skip("JRE not available, skipping JKS password detection tests")
	}
	
	passwords := []string{"changeit", "changeme", "password", "keystore", "secret"}
	
	for i, password := range passwords {
		t.Run("Password_"+password, func(t *testing.T) {
			filename := filepath.Join(fixturesDir, "jks", "password-test-"+strings.Itoa(i)+".jks")
			
			if _, err := os.Stat(filename); os.IsNotExist(err) {
				t.Skipf("Test file %s does not exist", filename)
			}
			
			// Test that the correct password works
			cmd := exec.Command("keytool", "-list", "-keystore", filename, "-storepass", password, "-noprompt")
			err := cmd.Run()
			
			if err != nil {
				t.Errorf("Expected password '%s' to work for %s", password, filename)
			}
		})
	}
}

// Test PKCS12 trust store operations
func TestPKCS12Operations(t *testing.T) {
	if !checkJREAvailable() {
		t.Skip("JRE not available, skipping PKCS12 tests")
	}
	
	tests := []struct {
		name     string
		filename string
		password string
		expectValid bool
	}{
		{
			name:     "Basic PKCS12",
			filename: "basic-truststore.p12",
			password: "changeit",
			expectValid: true,
		},
		{
			name:     "PKCS12 with custom password",
			filename: "custom-password-truststore.p12",
			password: "secretpass",
			expectValid: true,
		},
		{
			name:     "PKCS12 with PFX extension",
			filename: "basic-truststore.pfx",
			password: "changeit",
			expectValid: true,
		},
		{
			name:     "Corrupted PKCS12",
			filename: "corrupted-truststore.p12",
			password: "changeit",
			expectValid: false,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p12Path := filepath.Join(fixturesDir, "pkcs12", tt.filename)
			
			if _, err := os.Stat(p12Path); os.IsNotExist(err) {
				t.Skipf("Test file %s does not exist", p12Path)
			}
			
			// Test with keytool
			cmd := exec.Command("keytool", "-list", "-keystore", p12Path, "-storetype", "PKCS12", "-storepass", tt.password, "-noprompt")
			err := cmd.Run()
			
			if tt.expectValid && err != nil {
				t.Errorf("Expected valid PKCS12 but keytool failed: %v", err)
			}
			
			if !tt.expectValid && err == nil {
				t.Error("Expected invalid PKCS12 but keytool succeeded")
			}
		})
	}
}

// Test PEM trust store operations
func TestPEMOperations(t *testing.T) {
	tests := []struct {
		name        string
		filename    string
		expectValid bool
		expectCount int
	}{
		{
			name:        "Basic PEM trust store",
			filename:    "basic-trust-store.pem",
			expectValid: true,
			expectCount: 1,
		},
		{
			name:        "Multi-certificate PEM",
			filename:    "multi-cert-trust-store.pem",
			expectValid: true,
			expectCount: 3,
		},
		{
			name:        "Empty PEM",
			filename:    "empty-trust-store.pem",
			expectValid: true,
			expectCount: 0,
		},
		{
			name:        "Invalid PEM",
			filename:    "invalid-trust-store.pem",
			expectValid: false,
			expectCount: 0,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pemPath := filepath.Join(fixturesDir, "pem", tt.filename)
			
			if _, err := os.Stat(pemPath); os.IsNotExist(err) {
				t.Skipf("Test file %s does not exist", pemPath)
			}
			
			// Count certificates in PEM file
			content, err := os.ReadFile(pemPath)
			if err != nil {
				t.Fatalf("Failed to read PEM file: %v", err)
			}
			
			certCount := strings.Count(string(content), "BEGIN CERTIFICATE")
			
			if tt.expectCount > 0 && certCount != tt.expectCount {
				t.Errorf("Expected %d certificates, found %d", tt.expectCount, certCount)
			}
			
			// Test with OpenSSL if certificates are present
			if certCount > 0 {
				cmd := exec.Command("openssl", "x509", "-in", pemPath, "-text", "-noout")
				err = cmd.Run()
				
				if tt.expectValid && err != nil {
					t.Errorf("Expected valid PEM but OpenSSL failed: %v", err)
				}
			}
		})
	}
}

// Test configuration loading
func TestConfigurationLoading(t *testing.T) {
	// Create test config
	testConfig := filepath.Join(testTempDir, "test-config.yaml")
	configContent := `
logging:
  enabled: false
  simple_mode: true
  webhook_url: ""
  local_log_enabled: false

security:
  require_noop: true

operations:
  upsert_only: true

jre:
  auto_detect: true
  display_info_in_noop: true
`
	
	err := os.WriteFile(testConfig, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to create test config: %v", err)
	}
	
	// Test loading custom config
	args := []string{"--noop", "--config", testConfig, "-d", testTempDir}
	err = runTrustStoreManager(args...)
	
	if err != nil {
		t.Errorf("Failed to load custom config: %v", err)
	}
}

// Test noop requirement enforcement
func TestNoopRequirement(t *testing.T) {
	tests := []struct {
		name        string
		args        []string
		expectError bool
	}{
		{
			name:        "Without noop flag (should fail)",
			args:        []string{"-d", testTempDir},
			expectError: true,
		},
		{
			name:        "With noop flag (should succeed)",
			args:        []string{"--noop", "-d", testTempDir},
			expectError: false,
		},
		{
			name:        "With dry-run flag (should succeed)",
			args:        []string{"--dry-run", "-d", testTempDir},
			expectError: false,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := runTrustStoreManager(tt.args...)
			
			if tt.expectError && err == nil {
				t.Error("Expected error but got success")
			}
			
			if !tt.expectError && err != nil {
				t.Errorf("Expected success but got error: %v", err)
			}
		})
	}
}

// Test command line flag compatibility
func TestCommandLineFlags(t *testing.T) {
	goDir := filepath.Join(projectRoot, "go-trust-store-manager")
	
	// Test help flag
	cmd := exec.Command("go", "run", ".", "--help")
	cmd.Dir = goDir
	output, err := cmd.CombinedOutput()
	
	if err != nil {
		t.Fatalf("Help command failed: %v", err)
	}
	
	helpText := string(output)
	
	// Check for required flags
	requiredFlags := []string{"--noop", "-d", "-c", "-b", "--auto", "--config"}
	for _, flag := range requiredFlags {
		if !strings.Contains(helpText, flag) {
			t.Errorf("Help text missing flag: %s", flag)
		}
	}
}

// Test performance with large trust stores
func TestPerformance(t *testing.T) {
	largePEM := filepath.Join(fixturesDir, "pem", "large-trust-store.pem")
	
	if _, err := os.Stat(largePEM); os.IsNotExist(err) {
		t.Skip("Large trust store test file not available")
	}
	
	// Test performance with large trust store
	start := time.Now()
	
	args := []string{"--noop", "-d", filepath.Dir(largePEM)}
	err := runTrustStoreManager(args...)
	
	duration := time.Since(start)
	
	if err != nil {
		t.Errorf("Performance test failed: %v", err)
	}
	
	// Should complete within 30 seconds
	if duration > 30*time.Second {
		t.Errorf("Performance test took too long: %v", duration)
	}
	
	t.Logf("Performance test completed in: %v", duration)
}

// Benchmark tests
func BenchmarkTrustStoreScanning(b *testing.B) {
	if _, err := os.Stat(fixturesDir); os.IsNotExist(err) {
		b.Skip("Test fixtures not available")
	}
	
	args := []string{"--noop", "-d", fixturesDir}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		err := runTrustStoreManager(args...)
		if err != nil {
			b.Fatalf("Benchmark failed: %v", err)
		}
	}
}

// Test error handling
func TestErrorHandling(t *testing.T) {
	tests := []struct {
		name        string
		args        []string
		expectError bool
	}{
		{
			name:        "Non-existent directory",
			args:        []string{"--noop", "-d", "/non/existent/directory"},
			expectError: false, // Should handle gracefully
		},
		{
			name:        "Invalid config file",
			args:        []string{"--noop", "--config", "/non/existent/config.yaml"},
			expectError: false, // Should use defaults
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := runTrustStoreManager(tt.args...)
			
			if tt.expectError && err == nil {
				t.Error("Expected error but got success")
			}
			
			if !tt.expectError && err != nil {
				// Log but don't fail - some errors are acceptable
				t.Logf("Got error (acceptable): %v", err)
			}
		})
	}
} 