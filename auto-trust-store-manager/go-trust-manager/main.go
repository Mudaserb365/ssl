package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
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

// Global variables
var (
	summarySuccess int
	summaryFailure int
	logger         *log.Logger
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
	LogWriter       io.Writer
	WebhookURL      string    // URL to send logs to
	WebhookKey      string    // API key for the webhook
	WebhookEnabled  bool      // Whether webhook logging is enabled
	HostInfo        *HostInfo // Host information for logging
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

func main() {
	// Initialize default configuration
	config := Config{
		TargetDir:       ".",
		CertificatePath: "",
		LogFile:         fmt.Sprintf("trust_store_scan_%s.log", time.Now().Format("20060102_150405")),
		Passwords:       []string{"changeit", "changeme", "password", "keystore", "truststore", "secret", ""},
		KubernetesMode:  false,
		DockerMode:      false,
		RestartServices: false,
		BackupEnabled:   true,
		Verbose:         false,
		BaselineURL:     "",
		CompareOnly:     false,
		WebhookEnabled:  false,
		WebhookURL:      "",
		WebhookKey:      "",
	}

	// Parse command line flags
	flag.StringVar(&config.TargetDir, "d", config.TargetDir, "Target directory to scan")
	flag.StringVar(&config.TargetDir, "directory", config.TargetDir, "Target directory to scan")

	flag.StringVar(&config.CertificatePath, "c", config.CertificatePath, "Path to certificate to append")
	flag.StringVar(&config.CertificatePath, "certificate", config.CertificatePath, "Path to certificate to append")

	flag.StringVar(&config.LogFile, "l", config.LogFile, "Log file path")
	flag.StringVar(&config.LogFile, "log", config.LogFile, "Log file path")

	// Passwords flag requires special handling for space-separated list
	passwordsStr := flag.String("p", "", "Space-separated list of passwords to try (in quotes)")
	passwordsStrLong := flag.String("passwords", "", "Space-separated list of passwords to try (in quotes)")

	flag.BoolVar(&config.KubernetesMode, "k", config.KubernetesMode, "Enable Kubernetes mode")
	flag.BoolVar(&config.KubernetesMode, "kubernetes", config.KubernetesMode, "Enable Kubernetes mode")

	flag.BoolVar(&config.DockerMode, "D", config.DockerMode, "Enable Docker mode")
	flag.BoolVar(&config.DockerMode, "docker", config.DockerMode, "Enable Docker mode")

	flag.BoolVar(&config.RestartServices, "r", config.RestartServices, "Restart affected services")
	flag.BoolVar(&config.RestartServices, "restart", config.RestartServices, "Restart affected services")

	flag.BoolVar(&config.BackupEnabled, "n", !config.BackupEnabled, "Disable backup creation")
	flag.BoolVar(&config.BackupEnabled, "no-backup", !config.BackupEnabled, "Disable backup creation")
	config.BackupEnabled = !config.BackupEnabled // Flip since the flag is negative

	flag.BoolVar(&config.Verbose, "v", config.Verbose, "Enable verbose output")
	flag.BoolVar(&config.Verbose, "verbose", config.Verbose, "Enable verbose output")

	flag.StringVar(&config.BaselineURL, "b", config.BaselineURL, "URL to download baseline trust store")
	flag.StringVar(&config.BaselineURL, "baseline", config.BaselineURL, "URL to download baseline trust store")

	flag.BoolVar(&config.CompareOnly, "C", config.CompareOnly, "Only compare trust stores")
	flag.BoolVar(&config.CompareOnly, "compare-only", config.CompareOnly, "Only compare trust stores")

	// Add webhook flags
	flag.StringVar(&config.WebhookURL, "webhook-url", config.WebhookURL, "URL to send logs to (e.g., https://example.com/logs)")
	flag.StringVar(&config.WebhookKey, "webhook-key", config.WebhookKey, "API key for the webhook")
	webhookEnabled := flag.Bool("webhook", false, "Enable webhook logging")

	// Help flag handler
	help := flag.Bool("h", false, "Display help message")
	helpLong := flag.Bool("help", false, "Display help message")

	// Parse flags
	flag.Parse()

	// Handle help flag
	if *help || *helpLong {
		printUsage()
		os.Exit(0)
	}

	// Handle passwords list
	if *passwordsStr != "" {
		config.Passwords = strings.Fields(*passwordsStr)
	} else if *passwordsStrLong != "" {
		config.Passwords = strings.Fields(*passwordsStrLong)
	}

	// Set up logging
	logFile, err := os.Create(config.LogFile)
	if err != nil {
		fmt.Printf("Error creating log file: %v\n", err)
		os.Exit(1)
	}
	defer logFile.Close()
	config.LogWriter = io.MultiWriter(os.Stdout, logFile)
	logger = log.New(config.LogWriter, "", 0)

	// Setup webhook logging if enabled
	config.WebhookEnabled = *webhookEnabled
	if config.WebhookEnabled {
		if config.WebhookURL == "" {
			fmt.Println("Error: webhook-url is required when webhook logging is enabled")
			os.Exit(1)
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
			os.Exit(1)
		}
	}

	// Run the trust store manager
	err = runTrustStoreManager(config)
	if err != nil {
		logger.Printf("%sERROR: %s%s\n", colorRed, err, colorReset)
		os.Exit(1)
	}

	// Print summary
	printSummary(config)
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
	fmt.Println("  -h, --help                Display this help message")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Printf("  %s -d /path/to/project -c /path/to/cert.pem\n", os.Args[0])
	fmt.Printf("  %s --kubernetes --restart\n", os.Args[0])
	fmt.Printf("  %s --docker -v\n", os.Args[0])
	fmt.Printf("  %s -b https://example.com/baseline.pem -C\n", os.Args[0])
}

// runTrustStoreManager is the main function that orchestrates the trust store management process
func runTrustStoreManager(config Config) error {
	// Initial log entry
	if config.WebhookEnabled {
		logInfoWithWebhook(config, "Trust Store Scan started - "+time.Now().Format("2006-01-02 15:04:05"))
	} else {
		logInfo("Trust Store Scan started - " + time.Now().Format("2006-01-02 15:04:05"))
	}

	// Validate certificate path or generate a test certificate
	err := validateCertificate(&config)
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
func printSummary(config Config) {
	logger.Println()
	logger.Println("======== Trust Store Scan Summary ========")
	logger.Printf("Total successful operations: %d\n", summarySuccess)
	logger.Printf("Total failed operations: %d\n", summaryFailure)
	logger.Printf("Log file: %s\n", config.LogFile)
	logger.Println("==========================================")
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

// These updated logging functions will be used by the application to log with webhook support
func logInfoWithWebhook(config Config, message string) {
	logInfo(message)
	if config.WebhookEnabled {
		// Only send important logs to webhook to avoid flooding
		sendWebhookLog(config, "INFO", message)
	}
}

func logSuccessWithWebhook(config Config, message string) {
	logSuccess(message)
	if config.WebhookEnabled {
		sendWebhookLog(config, "SUCCESS", message)
	}
}

func logWarningWithWebhook(config Config, message string) {
	logWarning(message)
	if config.WebhookEnabled {
		sendWebhookLog(config, "WARNING", message)
	}
}

func logErrorWithWebhook(config Config, message string) {
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
func sendWebhookLog(config Config, level, message string) error {
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
