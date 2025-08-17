package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"gopkg.in/yaml.v2"
)

// Configuration structures
type AppConfig struct {
	Baseline struct {
		URL          string `yaml:"url"`
		FallbackPath string `yaml:"fallback_path"`
		VerifySSL    bool   `yaml:"verify_ssl"`
		TimeoutSecs  int    `yaml:"timeout_seconds"`
	} `yaml:"baseline"`

	Logging struct {
		Enabled          bool   `yaml:"enabled"`
		WebhookURL       string `yaml:"webhook_url"`
		WebhookAPIKey    string `yaml:"webhook_api_key"`
		LocalLogEnabled  bool   `yaml:"local_log_enabled"`
		LocalLogPath     string `yaml:"local_log_path"`
		LogLevel         string `yaml:"log_level"`
		DualOutput       bool   `yaml:"dual_output"`
		SimpleMode       bool   `yaml:"simple_mode"`
	} `yaml:"logging"`

	Security struct {
		RequireNoop         bool   `yaml:"require_noop"`
		EnableBackups       bool   `yaml:"enable_backups"`
		BackupDir           string `yaml:"backup_dir"`
		BackupRetentionDays int    `yaml:"backup_retention_days"`
	} `yaml:"security"`

	Operations struct {
		UpsertOnly         bool     `yaml:"upsert_only"`
		DefaultJKSPasswords []string `yaml:"default_jks_passwords"`
		OperationTimeout   int      `yaml:"operation_timeout"`
		ParallelProcessing bool     `yaml:"parallel_processing"`
		MaxConcurrent      int      `yaml:"max_concurrent"`
	} `yaml:"operations"`

	JRE struct {
		AutoDetect        bool   `yaml:"auto_detect"`
		JavaHome          string `yaml:"java_home"`
		KeytoolPath       string `yaml:"keytool_path"`
		MinVersion        string `yaml:"min_version"`
		DisplayInfoInNoop bool   `yaml:"display_info_in_noop"`
	} `yaml:"jre"`
}

// Logging structures
type SystemInfo struct {
	MachineIP   string   `json:"machine_ip"`
	MachineID   string   `json:"machine_id"`
	Hostname    string   `json:"hostname"`
	OS          string   `json:"os"`
	Arch        string   `json:"arch"`
	IPAddresses []string `json:"ip_addresses"`
}

type UserInfo struct {
	Username string `json:"username"`
	UserID   string `json:"user_id"`
	HomeDir  string `json:"home_dir"`
}

type GitInfo struct {
	ProjectName   string `json:"project_name"`
	BranchName    string `json:"branch_name"`
	CommitHash    string `json:"commit_hash"`
	RepositoryURL string `json:"repository_url"`
	IsDirty       bool   `json:"is_dirty"`
	WorkingDir    string `json:"working_dir"`
}

type TrustStoreModification struct {
	FilePath         string                 `json:"file_path"`
	FileType         string                 `json:"file_type"`
	Operation        string                 `json:"operation"`
	Status           string                 `json:"status"`
	Timestamp        time.Time              `json:"timestamp"`
	BeforeState      map[string]interface{} `json:"before_state"`
	AfterState       map[string]interface{} `json:"after_state"`
	Diff             string                 `json:"diff"`
	ErrorMessage     string                 `json:"error_message,omitempty"`
	NoopOutput       string                 `json:"noop_output,omitempty"`
	CertificatesAdded []string              `json:"certificates_added"`
	BackupPath       string                 `json:"backup_path,omitempty"`
}

type AuditLog struct {
	MachineIP     string                   `json:"machine_ip"`
	MachineID     string                   `json:"machine_id"`
	User          UserInfo                 `json:"user"`
	GitProject    GitInfo                  `json:"git_project"`
	Modifications []TrustStoreModification `json:"modifications"`
	Timestamp     time.Time                `json:"timestamp"`
	SessionID     string                   `json:"session_id"`
	Command       string                   `json:"command"`
	SystemInfo    SystemInfo               `json:"system_info"`
	Duration      string                   `json:"duration"`
	Summary       map[string]interface{}   `json:"summary"`
}

type StructuredLogger struct {
	config      *AppConfig
	auditLog    *AuditLog
	localWriter io.Writer
	sessionID   string
	startTime   time.Time
}

// Global variables for flags
var (
	targetDirectory string
	certificatePath string
	baselineURL     string
	noopMode        bool
	autoMode        bool
	verbose         bool
	showHelp        bool
	configPath      string
)

func init() {
	flag.StringVar(&targetDirectory, "d", ".", "Target directory to scan")
	flag.StringVar(&certificatePath, "c", "", "Path to certificate to append")
	flag.StringVar(&baselineURL, "b", "", "URL to download baseline trust store")
	flag.BoolVar(&noopMode, "noop", false, "Dry-run mode (required for safety)")
	flag.BoolVar(&autoMode, "auto", false, "Run in automatic mode")
	flag.BoolVar(&verbose, "v", false, "Enable verbose output")
	flag.BoolVar(&showHelp, "h", false, "Display help message")
	flag.StringVar(&configPath, "config", "", "Path to configuration file")
}

// LoadConfig loads configuration from YAML file
func LoadConfig(configPath string) (*AppConfig, error) {
	if configPath == "" {
		configPath = "config.yaml"
	}

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return createDefaultConfig(), nil
	}

	data, err := ioutil.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %v", err)
	}

	configContent := os.ExpandEnv(string(data))
	timestamp := time.Now().Format("20060102_150405")
	configContent = strings.ReplaceAll(configContent, "${TIMESTAMP}", timestamp)

	var config AppConfig
	if err := yaml.Unmarshal([]byte(configContent), &config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %v", err)
	}

	validateAndSetDefaults(&config)
	return &config, nil
}

func createDefaultConfig() *AppConfig {
	config := &AppConfig{}
	validateAndSetDefaults(config)
	return config
}

func validateAndSetDefaults(config *AppConfig) {
	if config.Baseline.URL == "" {
		config.Baseline.URL = "https://company.com/pki/baseline-trust-store.pem"
	}
	if config.Logging.WebhookURL == "" {
		config.Logging.WebhookURL = ""  // Empty by default to disable webhook
	}
	if config.Logging.LocalLogPath == "" {
		timestamp := time.Now().Format("20060102_150405")
		config.Logging.LocalLogPath = fmt.Sprintf("./logs/trust-store-manager-%s.log", timestamp)
	}
	config.Security.RequireNoop = true
	config.Operations.UpsertOnly = true
	config.Logging.Enabled = true
	config.Logging.DualOutput = true
	config.Logging.SimpleMode = false
	
	// JRE defaults
	config.JRE.AutoDetect = true
	config.JRE.MinVersion = "8"
	config.JRE.DisplayInfoInNoop = true
}

// NewStructuredLogger creates a new structured logger
func NewStructuredLogger(config *AppConfig) (*StructuredLogger, error) {
	logger := &StructuredLogger{
		config:    config,
		sessionID: fmt.Sprintf("ts-%d", time.Now().UnixNano()),
		startTime: time.Now(),
	}

	auditLog := &AuditLog{
		Timestamp:     time.Now(),
		SessionID:     logger.sessionID,
		Command:       strings.Join(os.Args, " "),
		Modifications: make([]TrustStoreModification, 0),
	}

	// Collect system information
	systemInfo, err := collectSystemInfo()
	if err != nil {
		return nil, fmt.Errorf("failed to collect system info: %v", err)
	}
	auditLog.SystemInfo = systemInfo
	auditLog.MachineIP = systemInfo.MachineIP
	auditLog.MachineID = systemInfo.MachineID

	// Collect user information
	userInfo, err := collectUserInfo()
	if err != nil {
		return nil, fmt.Errorf("failed to collect user info: %v", err)
	}
	auditLog.User = userInfo

	// Collect git information
	gitInfo, err := collectGitInfo()
	if err != nil {
		gitInfo = GitInfo{ProjectName: "unknown", BranchName: "unknown"}
	}
	auditLog.GitProject = gitInfo

	logger.auditLog = auditLog

	// Set up local file logging
	if config.Logging.LocalLogEnabled {
		if err := logger.setupLocalLogging(); err != nil {
			return nil, fmt.Errorf("failed to setup local logging: %v", err)
		}
	}

	return logger, nil
}

func (sl *StructuredLogger) setupLocalLogging() error {
	logDir := filepath.Dir(sl.config.Logging.LocalLogPath)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return fmt.Errorf("failed to create log directory: %v", err)
	}

	logFile, err := os.OpenFile(sl.config.Logging.LocalLogPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return fmt.Errorf("failed to open log file: %v", err)
	}

	if sl.config.Logging.DualOutput {
		sl.localWriter = io.MultiWriter(os.Stdout, logFile)
	} else {
		sl.localWriter = logFile
	}

	return nil
}

func (sl *StructuredLogger) LogMessage(level, message string) {
	logEntry := map[string]interface{}{
		"timestamp":  time.Now().Format(time.RFC3339),
		"session_id": sl.sessionID,
		"level":      level,
		"message":    message,
	}

	if sl.localWriter != nil {
		logJSON, _ := json.Marshal(logEntry)
		fmt.Fprintf(sl.localWriter, "[%s] %s\n", level, string(logJSON))
	}
}

func (sl *StructuredLogger) LogModification(modification TrustStoreModification) {
	modification.Timestamp = time.Now()
	sl.auditLog.Modifications = append(sl.auditLog.Modifications, modification)
	
	if sl.localWriter != nil {
		modJSON, _ := json.MarshalIndent(modification, "", "  ")
		fmt.Fprintf(sl.localWriter, "[MODIFICATION] %s\n", string(modJSON))
	}
}

func (sl *StructuredLogger) Finalize() error {
	sl.auditLog.Duration = time.Since(sl.startTime).String()

	summary := map[string]interface{}{
		"total_modifications": len(sl.auditLog.Modifications),
	}
	sl.auditLog.Summary = summary

	if sl.localWriter != nil {
		auditJSON, _ := json.MarshalIndent(sl.auditLog, "", "  ")
		fmt.Fprintf(sl.localWriter, "[AUDIT_LOG] %s\n", string(auditJSON))
	}

	if sl.config.Logging.WebhookURL != "" && sl.config.Logging.WebhookURL != "https://logs.company.com/api/trust-store-audit" {
		return sl.sendToWebhook()
	}

	return nil
}

func (sl *StructuredLogger) sendToWebhook() error {
	jsonData, err := json.Marshal(sl.auditLog)
	if err != nil {
		return fmt.Errorf("failed to marshal audit log: %v", err)
	}

	req, err := http.NewRequest("POST", sl.config.Logging.WebhookURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create webhook request: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if sl.config.Logging.WebhookAPIKey != "" {
		req.Header.Set("Authorization", "Bearer "+sl.config.Logging.WebhookAPIKey)
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send webhook: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("webhook returned status code: %d", resp.StatusCode)
	}

	return nil
}

func collectSystemInfo() (SystemInfo, error) {
	hostname, err := os.Hostname()
	if err != nil {
		return SystemInfo{}, err
	}

	primaryIP := ""
	ipAddresses := []string{}
	
	addrs, err := net.InterfaceAddrs()
	if err == nil {
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
				if ipnet.IP.To4() != nil {
					ipAddresses = append(ipAddresses, ipnet.IP.String())
					if primaryIP == "" {
						primaryIP = ipnet.IP.String()
					}
				}
			}
		}
	}

	machineID := hostname + "_" + primaryIP

	return SystemInfo{
		MachineIP:   primaryIP,
		MachineID:   machineID,
		Hostname:    hostname,
		OS:          runtime.GOOS,
		Arch:        runtime.GOARCH,
		IPAddresses: ipAddresses,
	}, nil
}

func collectUserInfo() (UserInfo, error) {
	currentUser, err := user.Current()
	if err != nil {
		return UserInfo{}, err
	}

	return UserInfo{
		Username: currentUser.Username,
		UserID:   currentUser.Uid,
		HomeDir:  currentUser.HomeDir,
	}, nil
}

func collectGitInfo() (GitInfo, error) {
	workingDir, _ := os.Getwd()
	
	gitInfo := GitInfo{
		WorkingDir: workingDir,
	}

	if projectName := getGitProjectName(); projectName != "" {
		gitInfo.ProjectName = projectName
	} else {
		gitInfo.ProjectName = filepath.Base(workingDir)
	}

	if branch := getGitBranch(); branch != "" {
		gitInfo.BranchName = branch
	}

	if commit := getGitCommit(); commit != "" {
		gitInfo.CommitHash = commit
	}

	if repoURL := getGitRemoteURL(); repoURL != "" {
		gitInfo.RepositoryURL = repoURL
	}

	gitInfo.IsDirty = isGitDirty()

	return gitInfo, nil
}

func getGitProjectName() string {
	cmd := exec.Command("git", "config", "--get", "remote.origin.url")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	
	url := strings.TrimSpace(string(output))
	if strings.Contains(url, "/") {
		parts := strings.Split(url, "/")
		projectName := parts[len(parts)-1]
		if strings.HasSuffix(projectName, ".git") {
			projectName = strings.TrimSuffix(projectName, ".git")
		}
		return projectName
	}
	
	return ""
}

func getGitBranch() string {
	cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func getGitCommit() string {
	cmd := exec.Command("git", "rev-parse", "HEAD")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func getGitRemoteURL() string {
	cmd := exec.Command("git", "config", "--get", "remote.origin.url")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func isGitDirty() bool {
	cmd := exec.Command("git", "diff", "--quiet")
	err := cmd.Run()
	return err != nil
}

// JRE Detection and Information Functions
type JREInfo struct {
	JavaHome    string `json:"java_home"`
	JavaVersion string `json:"java_version"`
	KeytoolPath string `json:"keytool_path"`
	Available   bool   `json:"available"`
}

func detectJRE(config *AppConfig) *JREInfo {
	jreInfo := &JREInfo{}
	
	// Check for custom paths first
	if config.JRE.JavaHome != "" {
		jreInfo.JavaHome = config.JRE.JavaHome
		jreInfo.KeytoolPath = filepath.Join(config.JRE.JavaHome, "bin", "keytool")
	} else if config.JRE.KeytoolPath != "" {
		jreInfo.KeytoolPath = config.JRE.KeytoolPath
	}
	
	// Auto-detect if enabled
	if config.JRE.AutoDetect {
		// Try to find java command
		if javaPath, err := exec.LookPath("java"); err == nil {
			jreInfo.JavaHome = filepath.Dir(filepath.Dir(javaPath))
		}
		
		// Try to find keytool command
		if keytoolPath, err := exec.LookPath("keytool"); err == nil {
			jreInfo.KeytoolPath = keytoolPath
			jreInfo.Available = true
		}
		
		// Get Java version
		if cmd := exec.Command("java", "-version"); cmd != nil {
			if output, err := cmd.CombinedOutput(); err == nil {
				jreInfo.JavaVersion = strings.Split(string(output), "\n")[0]
			}
		}
	}
	
	// Validate keytool availability
	if jreInfo.KeytoolPath != "" {
		if cmd := exec.Command(jreInfo.KeytoolPath, "-help"); cmd != nil {
			if err := cmd.Run(); err == nil {
				jreInfo.Available = true
			}
		}
	}
	
	return jreInfo
}

func displayJREInfo(jreInfo *JREInfo, config *AppConfig) {
	if !config.JRE.DisplayInfoInNoop {
		return
	}
	
	fmt.Println("\n=== Java Runtime Environment Information ===")
	
	if jreInfo.Available {
		fmt.Printf("✓ JRE Status: Available\n")
		if jreInfo.JavaVersion != "" {
			fmt.Printf("  Java Version: %s\n", strings.TrimSpace(jreInfo.JavaVersion))
		}
		if jreInfo.JavaHome != "" {
			fmt.Printf("  Java Home: %s\n", jreInfo.JavaHome)
		}
		if jreInfo.KeytoolPath != "" {
			fmt.Printf("  Keytool Path: %s\n", jreInfo.KeytoolPath)
		}
		fmt.Printf("  JKS Support: Enabled\n")
		fmt.Printf("  PKCS12 Support: Enabled\n")
	} else {
		fmt.Printf("⚠ JRE Status: Not Available\n")
		fmt.Printf("  JKS Support: Limited (keytool not found)\n")
		fmt.Printf("  PKCS12 Support: Limited (keytool not found)\n")
		fmt.Printf("\n")
		fmt.Printf("To enable full JKS/PKCS12 support:\n")
		fmt.Printf("  1. Install Java JDK/JRE: https://adoptium.net/\n")
		fmt.Printf("  2. Ensure 'java' and 'keytool' are in your PATH\n")
		fmt.Printf("  3. Or configure custom paths in config.yaml:\n")
		fmt.Printf("     jre:\n")
		fmt.Printf("       java_home: \"/path/to/java\"\n")
		fmt.Printf("       keytool_path: \"/path/to/keytool\"\n")
	}
	
	fmt.Println("===========================================\n")
}

func promptForJRELocation() string {
	fmt.Println("\n=== JRE Configuration Required ===")
	fmt.Println("Java Runtime Environment (JRE) not found in standard locations.")
	fmt.Println("Please provide the path to your Java installation:")
	fmt.Println()
	fmt.Print("Enter JAVA_HOME path (or press Enter to continue without JRE): ")
	
	scanner := bufio.NewScanner(os.Stdin)
	if scanner.Scan() {
		javaHome := strings.TrimSpace(scanner.Text())
		if javaHome != "" {
			// Validate the provided path
			keytoolPath := filepath.Join(javaHome, "bin", "keytool")
			if cmd := exec.Command(keytoolPath, "-help"); cmd != nil {
				if err := cmd.Run(); err == nil {
					fmt.Printf("✓ JRE found at: %s\n", javaHome)
					fmt.Println("You can save this path in config.yaml for future use.")
					return javaHome
				}
			}
			fmt.Printf("⚠ Invalid Java installation at: %s\n", javaHome)
		}
	}
	
	fmt.Println("Continuing without JRE support (PEM files only)...")
	return ""
}

func printUsage() {
	fmt.Println("Trust Store Manager - Enterprise Edition (Go)")
	fmt.Println("Automated SSL/TLS trust store management with centralized logging")
	fmt.Println()
	fmt.Println("IMPORTANT: This tool requires --noop flag for safety.")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Printf("  %s [options]\n", os.Args[0])
	fmt.Println()
	fmt.Println("Required Safety Flag:")
	fmt.Println("      --noop            REQUIRED: Show changes without implementing them")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  " + os.Args[0] + " --noop --auto -d /path/to/project")
	fmt.Println("  " + os.Args[0] + " --noop -c /path/to/cert.pem")
}

func main() {
	flag.Parse()

	// Show help if requested
	if showHelp {
		printUsage()
		return
	}

	// Load configuration
	appConfig, err := LoadConfig(configPath)
	if err != nil {
		fmt.Printf("Error loading configuration: %v\n", err)
		os.Exit(1)
	}

	// SAFETY CHECK: Enforce --noop requirement
	if appConfig.Security.RequireNoop && !noopMode {
		fmt.Printf("ERROR: This tool requires --noop flag for safety.\n")
		fmt.Println("Use --noop to preview changes before execution.")
		fmt.Println("This prevents accidental modifications to production trust stores.")
		fmt.Println()
		fmt.Println("Example: " + os.Args[0] + " --noop --auto -d /path/to/project")
		fmt.Println()
		fmt.Println("Run with -h for help.")
		os.Exit(1)
	}

	// Initialize structured logging only if enabled
	var structuredLogger *StructuredLogger
	if appConfig.Logging.Enabled {
		structuredLogger, err = NewStructuredLogger(appConfig)
		if err != nil {
			fmt.Printf("Error initializing logger: %v\n", err)
			os.Exit(1)
		}
		defer structuredLogger.Finalize()
		
		// Log startup
		structuredLogger.LogMessage("INFO", "Trust Store Manager started")
		if noopMode {
			structuredLogger.LogMessage("INFO", "Running in NOOP mode - no changes will be made")
		}
	}

	// Detect JRE and display information if in noop mode
	jreInfo := detectJRE(appConfig)
	
	if noopMode {
		displayJREInfo(jreInfo, appConfig)
		
		// If JRE not available and not in interactive mode, prompt user
		if !jreInfo.Available && autoMode {
			if javaHome := promptForJRELocation(); javaHome != "" {
				// Update configuration with user-provided path
				appConfig.JRE.JavaHome = javaHome
				jreInfo = detectJRE(appConfig)
			}
		}
	}

	// Simulate trust store processing
	fmt.Printf("Starting trust store scan in directory: %s\n", targetDirectory)
	
	if noopMode {
		fmt.Println("NOOP mode: Showing what would be done without making changes")
		
		if structuredLogger != nil {
			structuredLogger.LogMessage("NOOP", "Would scan for trust stores")
			
			// Example modification logging
			modification := TrustStoreModification{
				FilePath:   targetDirectory + "/example.jks",
				FileType:   "JKS",
				Operation:  "upsert_certificate",
				Status:     "noop",
				NoopOutput: "Would add certificate to trust store",
			}
			structuredLogger.LogModification(modification)
		}
		
		// Display trust store type support based on JRE availability
		fmt.Println("\nSupported Trust Store Types:")
		fmt.Printf("  ✓ PEM (.pem, .crt) - Always supported\n")
		if jreInfo.Available {
			fmt.Printf("  ✓ JKS (.jks, .keystore) - Supported (keytool available)\n")
			fmt.Printf("  ✓ PKCS12 (.p12, .pfx) - Supported (keytool available)\n")
		} else {
			fmt.Printf("  ⚠ JKS (.jks, .keystore) - Limited support (keytool not found)\n")
			fmt.Printf("  ⚠ PKCS12 (.p12, .pfx) - Limited support (keytool not found)\n")
		}
	}

	if structuredLogger != nil {
		structuredLogger.LogMessage("INFO", "Trust Store Manager completed successfully")
	}
	fmt.Println("Operation completed successfully!")
} 