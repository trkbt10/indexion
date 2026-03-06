package cmd

import (
	"github.com/spf13/cobra"
	"go.uber.org/zap"
)

var rootCmd = &cobra.Command{
	Use:   "go-service",
	Short: "A sample Go service",
}

func Execute() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	if err := rootCmd.Execute(); err != nil {
		logger.Fatal("command failed", zap.Error(err))
	}
}
