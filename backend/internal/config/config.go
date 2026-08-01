package config

import "os"

type Config struct {
	Port        string
	DatabaseURL string
	RedisAddr   string
	JWTSecret   string
	NodeName    string
	TURNHost    string
	TURNSecret  string
}

func Load() Config {
	return Config{
		Port:        getEnv("PORT", "8080"),
		DatabaseURL: getEnv("DATABASE_URL", "postgres://bully:bully@localhost:5432/bully?sslmode=disable"),
		RedisAddr:   getEnv("REDIS_ADDR", "localhost:6379"),
		JWTSecret:   getEnv("JWT_SECRET", "dev-secret-change-me"),
		NodeName:    getEnv("NODE_NAME", "Bully Node"),
		TURNHost:    getEnv("TURN_HOST", "127.0.0.1"),
		TURNSecret:  getEnv("TURN_SECRET", "dev-turn-secret-change-me"),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
