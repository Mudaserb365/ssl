package cmd

import (
	"github.com/spf13/cobra"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "trust-store-manager",
	Short: "A tool for managing certificate trust stores across platforms",
	Long: `Trust Store Manager is a comprehensive tool for managing certificate
trust stores across different platforms, runtimes, and environments.

It supports detecting, updating, and validating trust stores in Java, Python,
Node.js, and other environments. The tool can also validate certificate
trust chains to ensure proper security configuration.`,
	// Uncomment the following line if your bare application
	// has an action associated with it:
	// Run: func(cmd *cobra.Command, args []string) { },
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() error {
	return rootCmd.Execute()
}

func init() {
	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	rootCmd.PersistentFlags().StringP("config", "c", "", "config file (default is $HOME/.trust-store-manager.yaml)")
	rootCmd.PersistentFlags().BoolP("verbose", "v", false, "verbose output")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	rootCmd.Flags().BoolP("version", "V", false, "display version information")
}
