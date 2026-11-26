package httpapi

import (
	"net/http"
	"time"

	"rowe-server/internal/config"
	"rowe-server/internal/middleware"
	"rowe-server/internal/store"
)

// NewRouter builds the modular HTTP handler tree for RoweServer.
// Adding a new feature module (e.g. tasks, sharing, attachments) is simply mounting
// another handler group onto the versioned /api/v1 mux.
func NewRouter(st store.Store, cfg config.Config) http.Handler {
	mux := http.NewServeMux()

	hub := NewEventHub()
	authH := NewAuthHandler(st, cfg)
	vaultH := NewVaultHandler(st)
	syncH := NewSyncHandler(st, hub)

	requireAuth := middleware.RequireAuth(cfg.JWTSecret)
	globalLimiter := middleware.NewRateLimiter(cfg.RateLimitPerMin)
	authLimiter := middleware.NewRateLimiter(cfg.AuthRatePerMin)

	// Health check (unauthenticated)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":  "ok",
			"service": "rowe-server",
			"time":    time.Now().UTC().Format(time.RFC3339),
		})
	})

	// Auth routes (stricter IP rate limit)
	mux.Handle("POST /api/v1/auth/register", authLimiter.Middleware(http.HandlerFunc(authH.Register)))
	mux.Handle("POST /api/v1/auth/login", authLimiter.Middleware(http.HandlerFunc(authH.Login)))
	mux.Handle("POST /api/v1/auth/refresh", authLimiter.Middleware(http.HandlerFunc(authH.Refresh)))
	mux.Handle("POST /api/v1/auth/logout", authLimiter.Middleware(http.HandlerFunc(authH.Logout)))
	mux.Handle("GET /api/v1/auth/me", requireAuth(http.HandlerFunc(authH.Me)))
	mux.Handle("PUT /api/v1/auth/avatar", requireAuth(http.HandlerFunc(authH.PutAvatar)))
	mux.Handle("DELETE /api/v1/auth/avatar", requireAuth(http.HandlerFunc(authH.DeleteAvatar)))

	// Zero-knowledge PIN Vault Key Envelope routes
	mux.Handle("GET /api/v1/vault", requireAuth(http.HandlerFunc(vaultH.GetVault)))
	mux.Handle("PUT /api/v1/vault", requireAuth(http.HandlerFunc(vaultH.PutVault)))

	// Delta Sync, Real-Time SSE Hooks & Document routes
	mux.Handle("GET /api/v1/sync/events", requireAuth(http.HandlerFunc(syncH.Events)))
	mux.Handle("GET /api/v1/sync/pull", requireAuth(http.HandlerFunc(syncH.Pull)))
	mux.Handle("POST /api/v1/sync/push", requireAuth(http.HandlerFunc(syncH.Push)))
	mux.Handle("GET /api/v1/documents/{id}", requireAuth(http.HandlerFunc(syncH.GetDocument)))
	mux.Handle("DELETE /api/v1/documents/{id}", requireAuth(http.HandlerFunc(syncH.DeleteDocument)))

	var handler http.Handler = mux
	handler = globalLimiter.Middleware(handler)
	handler = middleware.CORS(cfg.CORSAllowedOrigins)(handler)
	handler = middleware.SecurityHeaders(handler)
	handler = middleware.RecoverAndLog(handler)
	return handler
}
