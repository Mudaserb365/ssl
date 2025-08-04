package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Global constants
const (
	// Color codes for terminal output
	colorRed    = "\033[0;31m"
	colorGreen  = "\033[0;32m"
	colorYellow = "\033[0;33m"
	colorBlue   = "\033[0;34m"
	colorReset  = "\033[0m"
)

// FileType represents the type of trust store file
type FileType string

const (
	FileTypeJKS     FileType = "JKS"
	FileTypePKCS12  FileType = "PKCS12"
	FileTypePEM     FileType = "PEM"
	FileTypeUnknown FileType = "UNKNOWN"
)

// Global variables
var (
	summarySuccess             int
	summaryFailure             int
	logger                     *log.Logger
	targetDirectory            string
	certificatePath            string
	logFile                    string
	passwords                  string
	kubernetesMode             bool
	dockerMode                 bool
	restartServices            bool
	noBackup                   bool
	verbose                    bool
	baselineURL                string
	compareOnly                bool
	WebhookEnabled             bool
	WebhookURL                 string
	WebhookAPIKey              string
	autoMode                   bool
	interactiveMode            bool
	showHelp                   bool
	noopMode                   bool  // New: dry-run mode
	summaryTrustStoresFound    int
	summaryTrustStoresModified int
)

// Config holds all configuration options
type Config struct {
	TargetDir       string
	CertificatePath string
	LogFile         string
	Passwords       []string
	KubernetesMode  bool
	DockerMode      bool
	RestartServices bool
	BackupEnabled   bool
	Verbose         bool
	BaselineURL     string
	CompareOnly     bool
	NoopMode        bool   // Dry-run mode - show changes without implementing them
	LogWriter       io.Writer
	WebhookEnabled  bool   // Enable webhook logging
	WebhookURL      string // URL to send logs to
	WebhookKey      string // API key for the webhook
	HostInfo        *HostInfo
}

// HostInfo contains information about the host system
type HostInfo struct {
	Hostname    string   `json:"hostname"`
	IPAddresses []string `json:"ip_addresses"`
	OS          string   `json:"os"`
	OSVersion   string   `json:"os_version"`
	Arch        string   `json:"arch"`
}

// LogEntry represents a log entry for webhook sending
type LogEntry struct {
	Timestamp string      `json:"timestamp"`
	Level     string      `json:"level"` // INFO, SUCCESS, WARNING, ERROR, DEBUG
	Message   string      `json:"message"`
	Host      *HostInfo   `json:"host"`
	Metadata  interface{} `json:"metadata,omitempty"`
}

func init() {
	// Help flag
	flag.BoolVar(&showHelp, "h", false, "Display help message")
	flag.BoolVar(&showHelp, "help", false, "Display help message")

	// Mode flags
	flag.BoolVar(&autoMode, "auto", false, "Run in automatic mode without interactive prompts")
	flag.BoolVar(&interactiveMode, "interactive", false, "Run in interactive walkthrough mode with step-by-step prompts")
	
	// Core operation flags
	flag.StringVar(&targetDirectory, "d", ".", "Target directory to scan")
	flag.StringVar(&targetDirectory, "directory", ".", "Target directory to scan")
	flag.StringVar(&certificatePath, "c", "", "Path to certificate to append (default: auto-generated)")
	flag.StringVar(&certificatePath, "certificate", "", "Path to certificate to append (default: auto-generated)")
	flag.StringVar(&logFile, "l", "", "Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)")
	flag.StringVar(&logFile, "log", "", "Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)")
	flag.StringVar(&passwords, "p", "", "Space-separated list of passwords to try (in quotes)")
	flag.StringVar(&passwords, "passwords", "", "Space-separated list of passwords to try (in quotes)")
	flag.StringVar(&baselineURL, "b", "", "URL to download baseline trust store for comparison")
	flag.StringVar(&baselineURL, "baseline", "", "URL to download baseline trust store for comparison")
	
	// Mode operation flags
	flag.BoolVar(&kubernetesMode, "k", false, "Enable Kubernetes mode (scan ConfigMaps and Secrets)")
	flag.BoolVar(&kubernetesMode, "kubernetes", false, "Enable Kubernetes mode (scan ConfigMaps and Secrets)")
	flag.BoolVar(&dockerMode, "D", false, "Enable Docker mode (scan common Docker trust store locations)")
	flag.BoolVar(&dockerMode, "docker", false, "Enable Docker mode (scan common Docker trust store locations)")
	flag.BoolVar(&restartServices, "r", false, "Restart affected services after modification")
	flag.BoolVar(&restartServices, "restart", false, "Restart affected services after modification")
	flag.BoolVar(&noBackup, "n", false, "Disable backup creation before modification")
	flag.BoolVar(&noBackup, "no-backup", false, "Disable backup creation before modification")
	flag.BoolVar(&verbose, "v", false, "Enable verbose output")
	flag.BoolVar(&verbose, "verbose", false, "Enable verbose output")
	flag.BoolVar(&compareOnly, "C", false, "Only compare trust stores, don't modify them")
	flag.BoolVar(&compareOnly, "compare-only", false, "Only compare trust stores, don't modify them")
	
	// New dry-run flag
	flag.BoolVar(&noopMode, "noop", false, "Show what changes would be made without implementing them (dry-run mode)")
	flag.BoolVar(&noopMode, "dry-run", false, "Show what changes would be made without implementing them (dry-run mode)")
	
	// Webhook flags
	flag.BoolVar(&WebhookEnabled, "webhook", false, "Enable webhook logging")
	flag.StringVar(&WebhookURL, "webhook-url", "", "URL to send logs to")
	flag.StringVar(&WebhookAPIKey, "webhook-key", "", "API key for the webhook")
}

func main() {
	flag.Parse()

	// Show help and exit if requested
	if showHelp {
		flag.Usage()
		os.Exit(0)
	}

	// Default to interactive mode if no mode is specified and no arguments are passed
	if !autoMode && !interactiveMode && flag.NFlag() == 0 {
		interactiveMode = true
	}

	// Set default log file if not specified
	if logFile == "" {
		logFile = fmt.Sprintf("trust_store_scan_%s.log", time.Now().Format("20060102_150405"))
	}

	// Parse passwords string into slice
	var passwordList []string
	if passwords != "" {
		passwordList = strings.Fields(passwords)
	} else {
		passwordList = []string{"changeit", "changeme", "password", "keystore", "truststore", "secret", ""}
	}

	// Initialize configuration from flags
	config := Config{
		TargetDir:       targetDirectory,
		CertificatePath: certificatePath,
		LogFile:         logFile,
		Passwords:       passwordList,
		KubernetesMode:  kubernetesMode,
		DockerMode:      dockerMode,
		RestartServices: restartServices,
		BackupEnabled:   !noBackup, // Note: flag is no-backup, so we invert it
		Verbose:         verbose,
		BaselineURL:     baselineURL,
		CompareOnly:     compareOnly,
		NoopMode:        noopMode,
		WebhookEnabled:  WebhookEnabled,
		WebhookURL:      WebhookURL,
		WebhookKey:      WebhookAPIKey,
	}

	// Run in interactive mode
	if interactiveMode {
		err := runInteractiveMode(&config)
		if err != nil {
			fmt.Printf("Error: %s\n", err)
			os.Exit(1)
		}
		os.Exit(0)
	}

	// Set up logging for automatic mode
	if !interactiveMode {
		logFile, err := os.Create(config.LogFile)
		if err != nil {
			fmt.Printf("Error creating log file: %v\n", err)
			os.Exit(1)
		}
		defer logFile.Close()
		config.LogWriter = io.MultiWriter(os.Stdout, logFile)
		logger = log.New(config.LogWriter, "", 0)

		// If noop mode is enabled, force compare-only and disable restarts/backups
		if config.NoopMode {
			config.CompareOnly = true
			config.RestartServices = false
			logNoop("Running in dry-run mode - no changes will be made")
		}
	}

	// Normal (automatic) mode execution
	err := runTrustStoreManager(&config)
	if err != nil {
		fmt.Printf("Error: %s\n", err)
		os.Exit(1)
	}
}

// printUsage displays the help message
func printUsage() {
	fmt.Println("Trust Store Manager")
	fmt.Println("This tool automates the discovery and modification of trust-store files.")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Printf("  %s [options]\n", os.Args[0])
	fmt.Println()
	fmt.Println("Options:")
	fmt.Println("  -d, --directory DIR       Target directory to scan (default: current directory)")
	fmt.Println("  -c, --certificate FILE    Path to certificate to append (default: auto-generated)")
	fmt.Println("  -l, --log FILE            Log file path (default: trust_store_scan_YYYYMMDD_HHMMSS.log)")
	fmt.Println("  -p, --passwords \"p1 p2\"   Space-separated list of passwords to try (in quotes)")
	fmt.Println("  -k, --kubernetes          Enable Kubernetes mode (scan ConfigMaps and Secrets)")
	fmt.Println("  -D, --docker              Enable Docker mode (scan common Docker trust store locations)")
	fmt.Println("  -r, --restart             Restart affected services after modification")
	fmt.Println("  -n, --no-backup           Disable backup creation before modification")
	fmt.Println("  -v, --verbose             Enable verbose output")
	fmt.Println("  -b, --baseline URL        URL to download baseline trust store for comparison")
	fmt.Println("  -C, --compare-only        Only compare trust stores, don't modify them")
	fmt.Println("      --noop, --dry-run     Show what changes would be made without implementing them")
	fmt.Println("  -h, --help                Display this help message")
	fmt.Println()
	fmt.Println("Mode Options:")
	fmt.Println("      --interactive         Run in interactive walkthrough mode (default if no arguments)")
	fmt.Println("      --auto                Run in automatic mode (non-interactive)")
	fmt.Println()
	fmt.Println("Webhook Options:")
	fmt.Println("      --webhook             Enable webhook logging")
	fmt.Println("      --webhook-url URL     URL to send logs to")
	fmt.Println("      --webhook-key KEY     API key for the webhook")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Printf("  %s --noop -d /path/to/project                     # Dry-run scan\n", os.Args[0])
	fmt.Printf("  %s -d /path/to/project -c /path/to/cert.pem       # Add certificate\n", os.Args[0])
	fmt.Printf("  %s --kubernetes --restart                         # Kubernetes mode\n", os.Args[0])
	fmt.Printf("  %s --docker -v                                    # Docker mode verbose\n", os.Args[0])
	fmt.Printf("  %s -b https://example.com/baseline.pem -C        # Compare with baseline\n", os.Args[0])
}

// runTrustStoreManager is the main function that orchestrates the trust store management process
func runTrustStoreManager(config *Config) error {
	// Initial log entry
	if config.WebhookEnabled {
		logInfoWithWebhook(config, "Trust Store Scan started - "+time.Now().Format("2006-01-02 15:04:05"))
	} else {
		logInfo("Trust Store Scan started - " + time.Now().Format("2006-01-02 15:04:05"))
	}

	// Validate certificate path or generate a test certificate
	err := validateCertificate(config)
	if err != nil {
		if config.WebhookEnabled {
			logErrorWithWebhook(config, fmt.Sprintf("Certificate validation failed: %v", err))
		}
		return err
	}

	// Download baseline store if URL provided
	if config.BaselineURL != "" {
		err := downloadBaselineStore(config)
		if err != nil {
			if config.WebhookEnabled {
				logErrorWithWebhook(config, fmt.Sprintf("Baseline download failed: %v", err))
			}
			return err
		}
		if config.WebhookEnabled {
			logSuccessWithWebhook(config, fmt.Sprintf("Downloaded baseline store from %s", config.BaselineURL))
		}
	}

	// Check for required tools
	err = checkDependencies(config)
	if err != nil {
		if config.WebhookEnabled {
			logErrorWithWebhook(config, fmt.Sprintf("Dependency check failed: %v", err))
		}
		return err
	}

	// Scan for trust stores based on mode
	if config.KubernetesMode {
		if config.WebhookEnabled {
			logInfoWithWebhook(config, "Starting Kubernetes scanning mode")
		}
		err = scanKubernetes(config)
	} else if config.DockerMode {
		if config.WebhookEnabled {
			logInfoWithWebhook(config, "Starting Docker scanning mode")
		}
		err = scanDocker(config)
	} else {
		if config.WebhookEnabled {
			logInfoWithWebhook(config, fmt.Sprintf("Starting directory scanning in %s", config.TargetDir))
		}
		err = scanDirectory(config)
	}

	if err != nil {
		if config.WebhookEnabled {
			logErrorWithWebhook(config, fmt.Sprintf("Scanning failed: %v", err))
		}
		return err
	}

	// Restart services if needed
	if config.RestartServices {
		err = restartAffectedServices(config)
		if err != nil {
			if config.WebhookEnabled {
				logWarningWithWebhook(config, fmt.Sprintf("Error restarting services: %v", err))
			} else {
				logWarning(fmt.Sprintf("Error restarting services: %v", err))
			}
		}
	}

	// Final success log
	if config.WebhookEnabled {
		logSuccessWithWebhook(config, "Trust Store Scan completed successfully")
	}

	return nil
}

// printSummary displays a summary of the operations performed
func printSummary(config *Config) {
	logger.Println()
	logger.Println("======== Trust Store Scan Summary ========")
	logger.Printf("Scanned directory: %s\n", config.TargetDir)
	logger.Printf("Trust stores found: %d\n", summaryTrustStoresFound)
	logger.Printf("Trust stores modified: %d\n", summaryTrustStoresModified)
	logger.Printf("Errors encountered: %d\n", summaryFailure)
	logger.Println("=========================================")
}

// Logging helper functions
func logInfo(message string) {
	logger.Printf("%s[INFO]%s %s\n", colorBlue, colorReset, message)
}

func logSuccess(message string) {
	logger.Printf("%s[SUCCESS]%s %s\n", colorGreen, colorReset, message)
	summarySuccess++
}

func logWarning(message string) {
	logger.Printf("%s[WARNING]%s %s\n", colorYellow, colorReset, message)
}

func logError(message string) {
	logger.Printf("%s[ERROR]%s %s\n", colorRed, colorReset, message)
	summaryFailure++
}

func logDebug(config Config, message string) {
	if config.Verbose {
		logger.Printf("[DEBUG] %s\n", message)
	}
}

// Noop mode logging functions
func logNoop(message string) {
	logger.Printf("%s[NOOP]%s %s\n", colorYellow, colorReset, message)
}

func logNoopAction(action, target string) {
	logger.Printf("%s[NOOP]%s Would %s: %s\n", colorYellow, colorReset, action, target)
}

func logNoopSkip(reason, target string) {
	logger.Printf("%s[NOOP]%s Skipping %s: %s\n", colorYellow, colorReset, target, reason)
}

// These updated logging functions will be used by the application to log with webhook support
func logInfoWithWebhook(config *Config, message string) {
	logInfo(message)
	if config.WebhookEnabled {
		// Only send important logs to webhook to avoid flooding
		sendWebhookLog(config, "INFO", message)
	}
}

func logSuccessWithWebhook(config *Config, message string) {
	logSuccess(message)
	if config.WebhookEnabled {
		sendWebhookLog(config, "SUCCESS", message)
	}
}

func logWarningWithWebhook(config *Config, message string) {
	logWarning(message)
	if config.WebhookEnabled {
		sendWebhookLog(config, "WARNING", message)
	}
}

func logErrorWithWebhook(config *Config, message string) {
	logError(message)
	if config.WebhookEnabled {
		sendWebhookLog(config, "ERROR", message)
	}
}

// collectHostInfo gathers information about the host system
func collectHostInfo() (*HostInfo, error) {
	hostInfo := &HostInfo{
		OS:        runtime.GOOS,
		Arch:      runtime.GOARCH,
		OSVersion: "", // Will try to get this
	}

	// Get hostname
	hostname, err := os.Hostname()
	if err == nil {
		hostInfo.Hostname = hostname
	} else {
		hostInfo.Hostname = "unknown"
	}

	// Get IP addresses
	addrs, err := net.InterfaceAddrs()
	if err == nil {
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
				if ipnet.IP.To4() != nil || ipnet.IP.To16() != nil {
					hostInfo.IPAddresses = append(hostInfo.IPAddresses, ipnet.IP.String())
				}
			}
		}
	}

	// Try to get OS version
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("cmd", "/c", "ver")
		output, err := cmd.Output()
		if err == nil {
			hostInfo.OSVersion = strings.TrimSpace(string(output))
		}
	case "darwin":
		cmd := exec.Command("sw_vers", "-productVersion")
		output, err := cmd.Output()
		if err == nil {
			hostInfo.OSVersion = strings.TrimSpace(string(output))
		}
	case "linux":
		// Try to get from /etc/os-release
		data, err := os.ReadFile("/etc/os-release")
		if err == nil {
			lines := strings.Split(string(data), "\n")
			for _, line := range lines {
				if strings.HasPrefix(line, "VERSION_ID=") {
					hostInfo.OSVersion = strings.Trim(line[11:], "\"")
					break
				}
			}
		}

		// If that fails, try lsb_release
		if hostInfo.OSVersion == "" {
			cmd := exec.Command("lsb_release", "-rs")
			output, err := cmd.Output()
			if err == nil {
				hostInfo.OSVersion = strings.TrimSpace(string(output))
			}
		}
	}

	return hostInfo, nil
}

// sendWebhookLog sends a log entry to the configured webhook
func sendWebhookLog(config *Config, level, message string) error {
	if !config.WebhookEnabled || config.WebhookURL == "" {
		return nil // Webhook not enabled, nothing to do
	}

	// Create log entry
	logEntry := LogEntry{
		Timestamp: time.Now().Format(time.RFC3339),
		Level:     level,
		Message:   message,
		Host:      config.HostInfo,
	}

	// Convert to JSON
	jsonData, err := json.Marshal(logEntry)
	if err != nil {
		return fmt.Errorf("failed to marshal log entry: %v", err)
	}

	// Prepare URL with API key if provided
	url := config.WebhookURL
	if config.WebhookKey != "" {
		if strings.Contains(url, "?") {
			url += "&apikey=" + config.WebhookKey
		} else {
			url += "?apikey=" + config.WebhookKey
		}
	}

	// Send HTTP request
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest("POST", url, strings.NewReader(string(jsonData)))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send webhook request: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("webhook returned error status: %d", resp.StatusCode)
	}

	return nil
}

// Add this function to detect project type
func detectProjectType(directory string) ([]string, error) {
	projectTypes := []string{}

	// Check for Java project indicators
	javaIndicators := []string{
		"pom.xml",      // Maven
		"build.gradle", // Gradle
		"*.jar",        // JAR files
		".java",        // Java source files
	}

	// Check for Python project indicators
	pythonIndicators := []string{
		"requirements.txt", // pip requirements
		"setup.py",         // Python setuptools
		"Pipfile",          // pipenv
		"*.py",             // Python source files
		"venv",             // Virtual environment
		".python-version",  // pyenv
	}

	// Check for Node.js project indicators
	nodeIndicators := []string{
		"package.json", // npm/yarn
		"node_modules", // npm/yarn modules directory
		"*.js",         // JavaScript files
		"*.ts",         // TypeScript files
	}

	// Look for Java indicators
	for _, indicator := range javaIndicators {
		matches, _ := filepath.Glob(filepath.Join(directory, indicator))
		if len(matches) > 0 {
			projectTypes = append(projectTypes, "java")
			break
		}
	}

	// Look for Python indicators
	for _, indicator := range pythonIndicators {
		matches, _ := filepath.Glob(filepath.Join(directory, indicator))
		if len(matches) > 0 {
			projectTypes = append(projectTypes, "python")
			break
		}
	}

	// Look for Node.js indicators
	for _, indicator := range nodeIndicators {
		matches, _ := filepath.Glob(filepath.Join(directory, indicator))
		if len(matches) > 0 {
			projectTypes = append(projectTypes, "nodejs")
			break
		}
	}

	return projectTypes, nil
}

// Add this function to prompt for user input
func promptForInput(prompt string, defaultValue string) string {
	reader := bufio.NewReader(os.Stdin)
	if defaultValue != "" {
		fmt.Printf("%s [%s]: ", prompt, defaultValue)
	} else {
		fmt.Printf("%s: ", prompt)
	}

	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(input)

	if input == "" {
		return defaultValue
	}
	return input
}

// Add this function to prompt for yes/no confirmation
func promptForConfirmation(prompt string) bool {
	reader := bufio.NewReader(os.Stdin)
	fmt.Printf("%s [y/N]: ", prompt)

	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(strings.ToLower(input))

	return input == "y" || input == "yes"
}

// Add this function to run interactive walkthrough mode
func runInteractiveMode(config *Config) error {
	fmt.Println("=== Trust Store Manager Interactive Walkthrough ===")
	fmt.Println("This wizard will guide you through the process of managing trust stores in your project.")
	fmt.Println()

	// Step 1: Project directory
	currentDir, _ := os.Getwd()
	projectDir := promptForInput("Enter the project directory path", currentDir)

	// Validate directory exists
	dirInfo, err := os.Stat(projectDir)
	if err != nil || !dirInfo.IsDir() {
		fmt.Println("Error: Invalid directory path.")
		return fmt.Errorf("invalid directory: %s", projectDir)
	}

	// Step 2: Detect project type
	fmt.Println("\nAnalyzing project directory...")
	projectTypes, err := detectProjectType(projectDir)
	if err != nil {
		fmt.Println("Warning: Could not automatically detect project type.")
	}

	var selectedType string
	if len(projectTypes) == 0 {
		fmt.Println("Could not automatically detect project type.")
		fmt.Println("Please select the primary runtime for your project:")
		fmt.Println("1. Java")
		fmt.Println("2. Python")
		fmt.Println("3. Node.js")
		fmt.Println("4. Other/Unknown")

		choice := promptForInput("Enter your choice (1-4)", "4")
		switch choice {
		case "1":
			selectedType = "java"
		case "2":
			selectedType = "python"
		case "3":
			selectedType = "nodejs"
		default:
			selectedType = "unknown"
		}
	} else if len(projectTypes) == 1 {
		selectedType = projectTypes[0]
		fmt.Printf("\nDetected %s project. Continue with this project type? ", selectedType)
		if !promptForConfirmation("") {
			fmt.Println("Please select the primary runtime for your project:")
			fmt.Println("1. Java")
			fmt.Println("2. Python")
			fmt.Println("3. Node.js")
			fmt.Println("4. Other/Unknown")

			choice := promptForInput("Enter your choice (1-4)", "4")
			switch choice {
			case "1":
				selectedType = "java"
			case "2":
				selectedType = "python"
			case "3":
				selectedType = "nodejs"
			default:
				selectedType = "unknown"
			}
		}
	} else {
		fmt.Println("\nDetected multiple project types:")
		for i, t := range projectTypes {
			fmt.Printf("%d. %s\n", i+1, t)
		}
		fmt.Printf("%d. Other/Unknown\n", len(projectTypes)+1)

		choice := promptForInput(fmt.Sprintf("Select primary project type (1-%d)", len(projectTypes)+1), "1")
		choiceNum := 0
		fmt.Sscanf(choice, "%d", &choiceNum)

		if choiceNum > 0 && choiceNum <= len(projectTypes) {
			selectedType = projectTypes[choiceNum-1]
		} else {
			selectedType = "unknown"
		}
	}

	// Step 3: Trust Store Options
	fmt.Printf("\nConfiguring options for %s project...\n", selectedType)

	// Option: Scan mode
	var scanMode string
	fmt.Println("\nSelect scan mode:")
	fmt.Println("1. Discovery only - Find and report trust stores without modifications")
	fmt.Println("2. Update existing - Update only existing trust stores")
	fmt.Println("3. Comprehensive - Find, create, and update trust stores")

	scanChoice := promptForInput("Enter your choice (1-3)", "1")
	switch scanChoice {
	case "2":
		scanMode = "update"
	case "3":
		scanMode = "comprehensive"
	default:
		scanMode = "discovery"
	}

	// Option: Certificate source
	var certPath string
	var generateCert bool

	fmt.Println("\nSelect certificate source:")
	fmt.Println("1. Auto-generate a new certificate")
	fmt.Println("2. Use an existing certificate file")
	fmt.Println("3. Download from URL")

	certChoice := promptForInput("Enter your choice (1-3)", "1")
	switch certChoice {
	case "2":
		certPath = promptForInput("Enter path to certificate file", "")
		generateCert = false
	case "3":
		certUrl := promptForInput("Enter URL to download certificate", "")
		// TODO: Implement download logic
		fmt.Println("Certificate will be downloaded from:", certUrl)
		generateCert = false
	default:
		generateCert = true
	}

	// Option: JKS passwords (for Java projects)
	var passwords []string
	if selectedType == "java" {
		fmt.Println("\nJava KeyStore (JKS) requires passwords for access.")
		defaultPwd := promptForInput("Enter default JKS password", "changeit")
		passwords = append(passwords, defaultPwd)

		if promptForConfirmation("Add additional passwords to try?") {
			for {
				additionalPwd := promptForInput("Enter additional password (or leave empty to finish)", "")
				if additionalPwd == "" {
					break
				}
				passwords = append(passwords, additionalPwd)
			}
		}
	}

	// Option: Enable webhook logging
	webhookEnabled := promptForConfirmation("\nEnable webhook logging for centralized monitoring?")

	var webhookUrl, webhookKey string
	if webhookEnabled {
		webhookUrl = promptForInput("Enter webhook URL", "")
		webhookKey = promptForInput("Enter webhook API key (optional)", "")
	}

	// Option: Advanced settings
	advancedOptions := promptForConfirmation("\nConfigure advanced options?")

	var backupEnabled bool = true
	var verboseMode bool = false

	if advancedOptions {
		verboseMode = promptForConfirmation("Enable verbose logging?")
		backupEnabled = promptForConfirmation("Create backups before modifying trust stores?")
	}

	// Summary and confirmation
	fmt.Println("\n=== Configuration Summary ===")
	fmt.Println("Project directory:", projectDir)
	fmt.Println("Project type:", selectedType)
	fmt.Println("Scan mode:", scanMode)

	if generateCert {
		fmt.Println("Certificate: Auto-generated")
	} else if certPath != "" {
		fmt.Println("Certificate path:", certPath)
	}

	if len(passwords) > 0 {
		fmt.Println("JKS passwords:", strings.Join(passwords, ", "))
	}

	if webhookEnabled {
		fmt.Println("Webhook URL:", webhookUrl)
		if webhookKey != "" {
			fmt.Println("Webhook API key: [REDACTED]")
		}
	}

	fmt.Println("Verbose mode:", verboseMode)
	fmt.Println("Create backups:", backupEnabled)

	if !promptForConfirmation("\nProceed with these settings?") {
		fmt.Println("Configuration cancelled. Exiting...")
		return nil
	}

	// Build and run command with gathered parameters
	fmt.Println("\nExecuting trust store management operation...")

	// Set config values based on interactive input
	config.TargetDir = projectDir
	config.BackupEnabled = backupEnabled
	config.Verbose = verboseMode
	config.WebhookEnabled = webhookEnabled
	config.WebhookURL = webhookUrl
	config.WebhookKey = webhookKey
	config.CertificatePath = certPath

	// Set scan mode flags
	config.CompareOnly = (scanMode == "discovery")

	// Set passwords if provided
	if len(passwords) > 0 {
		config.Passwords = passwords
	}

	// Set up logging
	logFile, err := os.Create(config.LogFile)
	if err != nil {
		fmt.Printf("Error creating log file: %v\n", err)
		return err
	}
	defer logFile.Close()
	config.LogWriter = io.MultiWriter(os.Stdout, logFile)
	logger = log.New(config.LogWriter, "", 0)

	// Setup webhook logging if enabled
	if config.WebhookEnabled {
		if config.WebhookURL == "" {
			fmt.Println("Error: webhook-url is required when webhook logging is enabled")
			return fmt.Errorf("missing webhook URL")
		}

		// Collect host information
		hostInfo, err := collectHostInfo()
		if err != nil {
			fmt.Printf("Warning: Failed to collect host information: %v\n", err)
			// Continue even if host info collection fails
		}
		config.HostInfo = hostInfo

		// Test webhook connection
		err = sendWebhookLog(config, "INFO", "Webhook logging initialized")
		if err != nil {
			fmt.Printf("Error: Failed to connect to webhook: %v\n", err)
			return err
		}
	}

	// Execute the trust store operations with the configured parameters
	err = runTrustStoreManager(config)
	if err != nil {
		fmt.Printf("Error: %s\n", err)
		return err
	}

	// Print summary
	printSummary(config)

	fmt.Println("\nOperation completed successfully!")
	return nil
}
