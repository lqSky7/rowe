package httpapi

import (
	"errors"
	"net/http"

	"rowe-server/internal/middleware"
	"rowe-server/internal/model"
	"rowe-server/internal/store"
)

// VaultHandler stores and serves the client-side PIN-wrapped 256-bit Note Vault Key.
// The server never sees the user's PIN or plaintext vault key.
type VaultHandler struct {
	store store.Store
}

func NewVaultHandler(st store.Store) *VaultHandler {
	return &VaultHandler{store: st}
}

type upsertVaultRequest struct {
	WrappedKey    string `json:"wrappedKey"`
	Salt          string `json:"salt"`
	Nonce         string `json:"nonce"`
	KDFIterations int    `json:"kdfIterations"`
	PinLength     int    `json:"pinLength"`
}

func (h *VaultHandler) GetVault(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	env, err := h.store.GetVaultKey(r.Context(), userID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeJSON(w, http.StatusOK, map[string]any{"vault": nil})
			return
		}
		writeError(w, http.StatusInternalServerError, "could not load vault envelope")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"vault": env})
}

func (h *VaultHandler) PutVault(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	var req upsertVaultRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.WrappedKey == "" || req.Salt == "" {
		writeError(w, http.StatusBadRequest, "wrappedKey and salt are required")
		return
	}
	if req.KDFIterations < 100_000 {
		writeError(w, http.StatusBadRequest, "kdfIterations must be at least 100000")
		return
	}
	if req.PinLength != 4 && req.PinLength != 6 {
		req.PinLength = 6
	}

	env := &model.VaultKeyEnvelope{
		UserID:        userID,
		WrappedKey:    req.WrappedKey,
		Salt:          req.Salt,
		Nonce:         req.Nonce,
		KDFIterations: req.KDFIterations,
		PinLength:     req.PinLength,
		Version:       1,
	}
	if err := h.store.UpsertVaultKey(r.Context(), env); err != nil {
		writeError(w, http.StatusInternalServerError, "could not save vault envelope")
		return
	}
	saved, _ := h.store.GetVaultKey(r.Context(), userID)
	writeJSON(w, http.StatusOK, map[string]any{"vault": saved})
}
