package cmd

import (
	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"github.com/example/go-service/internal/config"
	"github.com/example/go-service/internal/server"
)

var rootCmd = &cobra.Command{
	Use:   "go-service",
	Short: "A sample Go service",
	Run: func(cmd *cobra.Command, args []string) {
		logger, _ := zap.NewProduction()
		defer logger.Sync()

		cfg := config.Load()
		srv := server.New(cfg, logger)
		if err := srv.Run(cfg.Addr); err != nil {
			logger.Fatal("server exited", zap.Error(err))
		}
	},
}

func Execute() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	if err := rootCmd.Execute(); err != nil {
		logger.Fatal("command failed", zap.Error(err))
	}
}
