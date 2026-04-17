package server

import (
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/example/go-service/internal/config"
)

type Server struct {
	router *gin.Engine
	cfg    *config.Config
	log    *zap.Logger
}

func New(cfg *config.Config, log *zap.Logger) *Server {
	return &Server{
		router: gin.Default(),
		cfg:    cfg,
		log:    log,
	}
}

func (s *Server) Run(addr string) error {
	s.log.Info("starting server", zap.String("addr", addr), zap.String("env", s.cfg.Env))
	return s.router.Run(addr)
}
