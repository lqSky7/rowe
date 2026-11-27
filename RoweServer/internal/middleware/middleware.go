package middleware

import (
	"context"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"rowe-server/internal/crypto"
)

type ctxKey string

const (
	ctxUserIDKey ctxKey = "rowe_user_id"
	ctxEmailKey  ctxKey = "rowe_user_email"
)

func UserIDFromContext(ctx context.Context) string {
	v, _ := ctx.Value(ctxUserIDKey).(string)
	return v
}

func EmailFromContext(ctx context.Context) string {
	v, _ := ctx.Value(ctxEmailKey).(string)
	return v
}

// SecurityHeaders attaches strict baseline HTTP security headers.
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

// CORS configures cross-origin access for web/desktop clients.
func CORS(allowedOrigin string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// RecoverAndLog catches panics and logs request method, path, status, and latency.
func RecoverAndLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("PANIC %s %s: %v", r.Method, r.URL.Path, rec)
				http.Error(rw, `{"error":"internal server error"}`, http.StatusInternalServerError)
			}
			log.Printf("%s %s -> %d (%s)", r.Method, r.URL.Path, rw.status, time.Since(start).Round(time.Millisecond))
		}()
		next.ServeHTTP(rw, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Unwrap() http.ResponseWriter {
	return r.ResponseWriter
}

func (r *statusRecorder) Flush() {
	if f, ok := r.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// RequireAuth validates the Bearer access JWT and injects user ID into context.
func RequireAuth(jwtSecret []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if !strings.HasPrefix(authHeader, "Bearer ") {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUnauthorized)
				_, _ = w.Write([]byte(`{"error":"missing bearer token"}`))
				return
			}
			raw := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
			claims, err := crypto.VerifyJWT(jwtSecret, raw)
			if err != nil || claims.TokenType != "access" {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUnauthorized)
				_, _ = w.Write([]byte(`{"error":"invalid or expired token"}`))
				return
			}
			ctx := context.WithValue(r.Context(), ctxUserIDKey, claims.Subject)
			ctx = context.WithValue(ctx, ctxEmailKey, claims.Email)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RateLimiter implements a lightweight per-IP sliding token bucket to protect auth & vault endpoints.
type RateLimiter struct {
	mu        sync.Mutex
	buckets   map[string]*tokenBucket
	rate      float64
	burst     float64
	lastPrune time.Time
}

type tokenBucket struct {
	tokens   float64
	lastSeen time.Time
}

func NewRateLimiter(requestsPerMinute int) *RateLimiter {
	rl := &RateLimiter{
		buckets:   make(map[string]*tokenBucket),
		rate:      float64(requestsPerMinute) / 60.0,
		burst:     float64(requestsPerMinute),
		lastPrune: time.Now(),
	}
	return rl
}

func (rl *RateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIP(r)
		if !rl.allow(ip) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"rate limit exceeded, please try again shortly"}`))
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (rl *RateLimiter) allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	now := time.Now()
	// Periodically evict stale IP buckets (idle > 10m) to bound memory usage.
	if now.Sub(rl.lastPrune) >= 5*time.Minute {
		for k, bucket := range rl.buckets {
			if now.Sub(bucket.lastSeen) > 10*time.Minute {
				delete(rl.buckets, k)
			}
		}
		rl.lastPrune = now
	}
	b, ok := rl.buckets[key]
	if !ok {
		rl.buckets[key] = &tokenBucket{tokens: rl.burst - 1, lastSeen: now}
		return true
	}
	elapsed := now.Sub(b.lastSeen).Seconds()
	b.tokens = minFloat(rl.burst, b.tokens+elapsed*rl.rate)
	b.lastSeen = now
	if b.tokens < 1.0 {
		return false
	}
	b.tokens -= 1.0
	return true
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func minFloat(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}
