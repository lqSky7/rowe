package httpapi

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"rowe-server/internal/config"
	"rowe-server/internal/crypto"
	"rowe-server/internal/middleware"
	"rowe-server/internal/model"
	"rowe-server/internal/store"
)

type AuthHandler struct {
	store store.Store
	cfg   config.Config
}

func NewAuthHandler(st store.Store, cfg config.Config) *AuthHandler {
	return &AuthHandler{store: st, cfg: cfg}
}

type registerRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"displayName"`
	Device      string `json:"device"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Device   string `json:"device"`
}

type refreshRequest struct {
	RefreshToken string `json:"refreshToken"`
	Device       string `json:"device"`
}

type authResponse struct {
	AccessToken  string                  `json:"accessToken"`
	RefreshToken string                  `json:"refreshToken"`
	ExpiresIn    int64                   `json:"expiresIn"`
	User         *model.User             `json:"user"`
	Vault        *model.VaultKeyEnvelope `json:"vault,omitempty"`
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))
	if !strings.Contains(email, "@") || len(email) < 5 {
		writeError(w, http.StatusBadRequest, "valid email is required")
		return
	}
	if len(req.Password) < 8 {
		writeError(w, http.StatusBadRequest, "password must be at least 8 characters")
		return
	}

	hash, err := crypto.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	displayName := strings.TrimSpace(req.DisplayName)
	if displayName == "" {
		displayName = strings.Split(email, "@")[0]
	}

	user := &model.User{
		ID:           crypto.NewID(),
		Email:        email,
		DisplayName:  displayName,
		PasswordHash: hash,
	}
	if err := h.store.CreateUser(r.Context(), user); err != nil {
		if errors.Is(err, store.ErrAlreadyExists) {
			writeError(w, http.StatusConflict, "an account with that email already exists")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not create account")
		return
	}

	resp, err := h.issueTokens(r, user, req.Device)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not issue session tokens")
		return
	}
	writeJSON(w, http.StatusCreated, resp)
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))
	user, err := h.store.GetUserByEmail(r.Context(), email)
	if err != nil || !crypto.VerifyPassword(req.Password, user.PasswordHash) {
		writeError(w, http.StatusUnauthorized, "invalid email or password")
		return
	}

	resp, err := h.issueTokens(r, user, req.Device)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not issue session tokens")
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.RefreshToken) == "" {
		writeError(w, http.StatusBadRequest, "refreshToken is required")
		return
	}

	hash := crypto.SHA256Hex(req.RefreshToken)
	sess, err := h.store.GetRefreshSessionByHash(r.Context(), hash)
	if err != nil || sess.ExpiresAt.Before(time.Now().UTC()) {
		writeError(w, http.StatusUnauthorized, "refresh token invalid or expired")
		return
	}

	// Rotate refresh token: revoke old token immediately.
	_ = h.store.DeleteRefreshSessionByHash(r.Context(), hash)

	user, err := h.store.GetUserByID(r.Context(), sess.UserID)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "account not found")
		return
	}

	device := req.Device
	if device == "" {
		device = sess.Device
	}
	resp, err := h.issueTokens(r, user, device)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not refresh session")
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.RefreshToken != "" {
		_ = h.store.DeleteRefreshSessionByHash(r.Context(), crypto.SHA256Hex(req.RefreshToken))
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *AuthHandler) Me(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	user, err := h.store.GetUserByID(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	vault, _ := h.store.GetVaultKey(r.Context(), userID)
	writeJSON(w, http.StatusOK, map[string]any{
		"user":  user,
		"vault": vault,
	})
}

const (
	maxAvatarDecodedBytes = 5 * 1024 * 1024 // 5 MB hard cap
	maxAvatarRequestBytes = 7 * 1024 * 1024 // ~6.67 MB base64 + JSON overhead
)

type updateAvatarRequest struct {
	AvatarBase64 string `json:"avatarBase64"`
}

func (h *AuthHandler) PutAvatar(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	r.Body = http.MaxBytesReader(w, r.Body, maxAvatarRequestBytes)
	var req updateAvatarRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			writeError(w, http.StatusRequestEntityTooLarge, "profile picture exceeds 5 MB limit")
			return
		}
		writeError(w, http.StatusBadRequest, "invalid avatar payload")
		return
	}

	rawB64 := strings.TrimSpace(req.AvatarBase64)
	if idx := strings.Index(rawB64, ","); idx != -1 && strings.HasPrefix(rawB64, "data:") {
		rawB64 = strings.TrimSpace(rawB64[idx+1:])
	}
	if rawB64 == "" {
		writeError(w, http.StatusBadRequest, "avatarBase64 is required")
		return
	}

	decoded, err := base64.StdEncoding.DecodeString(rawB64)
	if err != nil {
		decoded, err = base64.RawStdEncoding.DecodeString(rawB64)
		if err != nil {
			writeError(w, http.StatusBadRequest, "avatarBase64 must be valid base64")
			return
		}
	}
	if len(decoded) == 0 {
		writeError(w, http.StatusBadRequest, "profile picture is empty")
		return
	}
	if len(decoded) > maxAvatarDecodedBytes {
		writeError(w, http.StatusRequestEntityTooLarge, "profile picture exceeds 5 MB limit")
		return
	}

	mimeType := http.DetectContentType(decoded)
	switch mimeType {
	case "image/png", "image/jpeg", "image/webp", "image/gif":
	default:
		writeError(w, http.StatusBadRequest, "profile picture must be PNG, JPEG, WebP, or GIF")
		return
	}

	cleanB64 := base64.StdEncoding.EncodeToString(decoded)
	if err := h.store.UpdateUserAvatar(r.Context(), userID, cleanB64, mimeType); err != nil {
		writeError(w, http.StatusInternalServerError, "could not save profile picture")
		return
	}
	user, err := h.store.GetUserByID(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load updated profile")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": user})
}

func (h *AuthHandler) DeleteAvatar(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	if err := h.store.UpdateUserAvatar(r.Context(), userID, "", ""); err != nil {
		writeError(w, http.StatusInternalServerError, "could not remove profile picture")
		return
	}
	user, err := h.store.GetUserByID(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load updated profile")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": user})
}

func (h *AuthHandler) issueTokens(r *http.Request, user *model.User, device string) (*authResponse, error) {
	now := time.Now().UTC()
	accessToken, err := crypto.SignJWT(h.cfg.JWTSecret, crypto.JWTClaims{
		Subject:   user.ID,
		Email:     user.Email,
		TokenType: "access",
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(h.cfg.AccessTokenTTL).Unix(),
	})
	if err != nil {
		return nil, err
	}

	rawRefresh, err := crypto.NewOpaqueToken()
	if err != nil {
		return nil, err
	}
	sess := &model.RefreshSession{
		ID:        crypto.NewID(),
		UserID:    user.ID,
		TokenHash: crypto.SHA256Hex(rawRefresh),
		Device:    device,
		ExpiresAt: now.Add(h.cfg.RefreshTokenTTL),
		CreatedAt: now,
	}
	if err := h.store.CreateRefreshSession(r.Context(), sess); err != nil {
		return nil, err
	}

	vault, _ := h.store.GetVaultKey(r.Context(), user.ID)
	return &authResponse{
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
		ExpiresIn:    int64(h.cfg.AccessTokenTTL.Seconds()),
		User:         user,
		Vault:        vault,
	}, nil
}
