package config

type Config struct {
	Addr string
	Env  string
}

func Load() *Config {
	return &Config{
		Addr: ":8080",
		Env:  "development",
	}
}
