package config

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"os"
	"strconv"
	"time"
)

// Config holds all runtime configuration loaded from environment variables.
type Config struct {
	Addr             string
	DBPath           string
	JWTSecret        []byte
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	CORSAllowedOrigins string
	RateLimitPerMin  int
	AuthRatePerMin   int
}

func Load() Config {
	addr := envOr("ROWE_ADDR", ":8080")
	dbPath := envOr("ROWE_DB_PATH", "./data/rowe.db")
	cors := envOr("ROWE_CORS_ORIGINS", "*")
	ratePerMin := envIntOr("ROWE_RATE_LIMIT_PER_MIN", 180)
	authRatePerMin := envIntOr("ROWE_AUTH_RATE_PER_MIN", 20)

	secret := os.Getenv("ROWE_JWT_SECRET")
	if len(secret) < 32 {
		if secret != "" {
			log.Println("WARN: ROWE_JWT_SECRET is shorter than 32 bytes; please set a strong random secret in production.")
		} else {
			// Dev fallback: generate ephemeral secret so the server starts cleanly locally.
			buf := make([]byte, 32)
			_, _ = rand.Read(buf)
			secret = hex.EncodeToString(buf)
			log.Println("WARN: ROWE_JWT_SECRET not set; using ephemeral secret (tokens reset on restart). Set ROWE_JWT_SECRET in production.")
		}
	}

	return Config{
		Addr:               addr,
		DBPath:             dbPath,
		JWTSecret:          []byte(secret),
		AccessTokenTTL:     15 * time.Minute,
		RefreshTokenTTL:    30 * 24 * time.Hour,
		CORSAllowedOrigins: cors,
		RateLimitPerMin:    ratePerMin,
		AuthRatePerMin:     authRatePerMin,
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOr(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return fallback
}
