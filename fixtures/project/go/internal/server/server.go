package server

import (
	"github.com/gin-gonic/gin"
)

type Server struct {
	router *gin.Engine
}

func New() *Server {
	return &Server{
		router: gin.Default(),
	}
}

func (s *Server) Run(addr string) error {
	return s.router.Run(addr)
}
