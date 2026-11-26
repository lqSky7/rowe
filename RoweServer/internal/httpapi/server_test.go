package httpapi_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"rowe-server/internal/config"
	"rowe-server/internal/httpapi"
	"rowe-server/internal/store"
)

func newTestServer(t *testing.T) (http.Handler, func()) {
	t.Helper()
	st, err := store.NewSQLiteStore(":memory:")
	if err != nil {
		t.Fatalf("open in-memory sqlite: %v", err)
	}
	cfg := config.Config{
		Addr:               ":0",
		DBPath:             ":memory:",
		JWTSecret:          []byte("0123456789abcdef0123456789abcdef_test_secret"),
		AccessTokenTTL:     15 * time.Minute,
		RefreshTokenTTL:    24 * time.Hour,
		CORSAllowedOrigins: "*",
		RateLimitPerMin:    500,
		AuthRatePerMin:     100,
	}
	return httpapi.NewRouter(st, cfg), func() { _ = st.Close() }
}

func doJSON(t *testing.T, handler http.Handler, method, path, bearer string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatalf("encode json: %v", err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func TestEndToEndAuthVaultAndZeroKnowledgeSync(t *testing.T) {
	handler, cleanup := newTestServer(t)
	defer cleanup()

	// 1. Health check
	res := doJSON(t, handler, http.MethodGet, "/healthz", "", nil)
	if res.Code != http.StatusOK {
		t.Fatalf("healthz expected 200, got %d", res.Code)
	}

	// 2. Register
	res = doJSON(t, handler, http.MethodPost, "/api/v1/auth/register", "", map[string]any{
		"email":       "diljot@rowe.app",
		"password":    "SuperSecurePass123",
		"displayName": "Diljot",
		"device":      "MacBook Pro",
	})
	if res.Code != http.StatusCreated {
		t.Fatalf("register expected 201, got %d: %s", res.Code, res.Body.String())
	}
	var regResp struct {
		AccessToken  string `json:"accessToken"`
		RefreshToken string `json:"refreshToken"`
		User         struct {
			ID    string `json:"id"`
			Email string `json:"email"`
		} `json:"user"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &regResp); err != nil {
		t.Fatalf("decode register: %v", err)
	}
	if regResp.AccessToken == "" || regResp.RefreshToken == "" {
		t.Fatalf("expected non-empty access & refresh tokens")
	}

	// 3. Duplicate email rejected
	dup := doJSON(t, handler, http.MethodPost, "/api/v1/auth/register", "", map[string]any{
		"email":    "diljot@rowe.app",
		"password": "AnotherPassword123",
	})
	if dup.Code != http.StatusConflict {
		t.Fatalf("duplicate register expected 409, got %d", dup.Code)
	}

	// 4. Refresh token rotation
	ref := doJSON(t, handler, http.MethodPost, "/api/v1/auth/refresh", "", map[string]any{
		"refreshToken": regResp.RefreshToken,
	})
	if ref.Code != http.StatusOK {
		t.Fatalf("refresh expected 200, got %d: %s", ref.Code, ref.Body.String())
	}
	var refResp struct {
		AccessToken  string `json:"accessToken"`
		RefreshToken string `json:"refreshToken"`
	}
	_ = json.Unmarshal(ref.Body.Bytes(), &refResp)

	// Reusing old refresh token must fail
	reused := doJSON(t, handler, http.MethodPost, "/api/v1/auth/refresh", "", map[string]any{
		"refreshToken": regResp.RefreshToken,
	})
	if reused.Code != http.StatusUnauthorized {
		t.Fatalf("reused refresh token expected 401, got %d", reused.Code)
	}

	token := refResp.AccessToken

	// 5. Save Zero-Knowledge Vault Key Envelope (PIN-wrapped on client)
	putVault := doJSON(t, handler, http.MethodPut, "/api/v1/vault", token, map[string]any{
		"wrappedKey":    "BASE64_CIPHERTEXT_WRAPPED_VAULT_KEY",
		"salt":          "BASE64_RANDOM_SALT",
		"nonce":         "BASE64_GCM_NONCE",
		"kdfIterations": 210000,
		"pinLength":     6,
	})
	if putVault.Code != http.StatusOK {
		t.Fatalf("put vault expected 200, got %d: %s", putVault.Code, putVault.Body.String())
	}

	// 6. Push both an unlocked note and a locked E2EE note (even if payloadJson is accidentally sent, server strips it)
	push := doJSON(t, handler, http.MethodPost, "/api/v1/sync/push", token, map[string]any{
		"documents": []map[string]any{
			{
				"id":          "doc-normal",
				"spaceId":     "space-1",
				"title":       "Daily Notes",
				"isLocked":    false,
				"payloadJson": `{"blocks":[{"content":"hello"}]}`,
			},
			{
				"id":               "doc-secret",
				"spaceId":          "space-1",
				"title":            "Private Journal",
				"isLocked":         true,
				"payloadJson":      `{"blocks":[{"content":"SHOULD_BE_STRIPPED"}]}`,
				"encryptedPayload": "AES256GCM_OPAQUE_CIPHERTEXT_BASE64",
			},
		},
	})
	if push.Code != http.StatusOK {
		t.Fatalf("sync push expected 200, got %d: %s", push.Code, push.Body.String())
	}

	// 7. Pull and verify zero-knowledge invariant on locked note
	pull := doJSON(t, handler, http.MethodGet, "/api/v1/sync/pull?since=0", token, nil)
	if pull.Code != http.StatusOK {
		t.Fatalf("sync pull expected 200, got %d: %s", pull.Code, pull.Body.String())
	}
	var pullResp struct {
		Documents []struct {
			ID               string `json:"id"`
			IsLocked         bool   `json:"isLocked"`
			PayloadJSON      string `json:"payloadJson"`
			EncryptedPayload string `json:"encryptedPayload"`
		} `json:"documents"`
	}
	_ = json.Unmarshal(pull.Body.Bytes(), &pullResp)
	if len(pullResp.Documents) != 2 {
		t.Fatalf("expected 2 synced docs, got %d", len(pullResp.Documents))
	}
	for _, d := range pullResp.Documents {
		if d.ID == "doc-secret" {
			if !d.IsLocked || d.PayloadJSON != "" || d.EncryptedPayload != "AES256GCM_OPAQUE_CIPHERTEXT_BASE64" {
				t.Fatalf("zero-knowledge invariant violated: %+v", d)
			}
		}
	}
}
