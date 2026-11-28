package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"rowe-server/internal/config"
	"rowe-server/internal/httpapi"
	"rowe-server/internal/middleware"
	"rowe-server/internal/model"
	"rowe-server/internal/store"
)

func registerAndGetToken(t *testing.T, handler http.Handler, email string) string {
	t.Helper()
	res := doJSON(t, handler, http.MethodPost, "/api/v1/auth/register", "", map[string]any{
		"email":       email,
		"password":    "StrongPass12345!",
		"displayName": "Test User",
		"device":      "TestDevice",
	})
	if res.Code != http.StatusCreated {
		t.Fatalf("register failed: %d %s", res.Code, res.Body.String())
	}
	var out struct {
		AccessToken string `json:"accessToken"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &out); err != nil || out.AccessToken == "" {
		t.Fatalf("invalid register response: %v %s", err, res.Body.String())
	}
	return out.AccessToken
}

func TestSyncPushMultiDocBatchAndDeleteTombstonePropagation(t *testing.T) {
	handler, cleanup := newTestServer(t)
	defer cleanup()

	token := registerAndGetToken(t, handler, "batch@rowe.app")

	// 1. Push 5 documents in a single atomic batch
	docs := make([]map[string]any, 0, 5)
	for i := 0; i < 5; i++ {
		docs = append(docs, map[string]any{
			"id":          "doc-batch-" + string(rune('a'+i)),
			"spaceId":     "space-1",
			"title":       "Batch Doc",
			"isLocked":    false,
			"payloadJson": `[{"id":"blk-1","content":"hello"}]`,
		})
	}
	pushRes := doJSON(t, handler, http.MethodPost, "/api/v1/sync/push", token, map[string]any{
		"documents": docs,
	})
	if pushRes.Code != http.StatusOK {
		t.Fatalf("batch push expected 200, got %d: %s", pushRes.Code, pushRes.Body.String())
	}

	var pushBody struct {
		Documents  []map[string]any `json:"documents"`
		ServerTime int64            `json:"serverTime"`
	}
	if err := json.Unmarshal(pushRes.Body.Bytes(), &pushBody); err != nil {
		t.Fatalf("decode push body: %v", err)
	}
	if len(pushBody.Documents) != 5 {
		t.Fatalf("expected 5 saved docs, got %d", len(pushBody.Documents))
	}

	// 2. Soft-delete one document and verify sync/pull returns tombstone
	beforeDelete := pushBody.ServerTime
	time.Sleep(5 * time.Millisecond)

	delRes := doJSON(t, handler, http.MethodDelete, "/api/v1/documents/doc-batch-c", token, nil)
	if delRes.Code != http.StatusOK {
		t.Fatalf("delete doc expected 200, got %d: %s", delRes.Code, delRes.Body.String())
	}

	// Idempotent second delete succeeds cleanly
	delRes2 := doJSON(t, handler, http.MethodDelete, "/api/v1/documents/doc-batch-c", token, nil)
	if delRes2.Code != http.StatusOK {
		t.Fatalf("idempotent delete expected 200, got %d", delRes2.Code)
	}

	pullRes := doJSON(t, handler, http.MethodGet, "/api/v1/sync/pull?since=0", token, nil)
	if pullRes.Code != http.StatusOK {
		t.Fatalf("pull expected 200, got %d", pullRes.Code)
	}
	var pullBody struct {
		Documents []struct {
			ID        string  `json:"id"`
			DeletedAt *string `json:"deletedAt"`
		} `json:"documents"`
		ServerTime int64 `json:"serverTime"`
	}
	if err := json.Unmarshal(pullRes.Body.Bytes(), &pullBody); err != nil {
		t.Fatalf("decode pull: %v", err)
	}
	if pullBody.ServerTime < beforeDelete {
		t.Fatalf("serverTime went backwards: %d < %d", pullBody.ServerTime, beforeDelete)
	}
	foundDeleted := false
	for _, d := range pullBody.Documents {
		if d.ID == "doc-batch-c" && d.DeletedAt != nil && *d.DeletedAt != "" {
			foundDeleted = true
		}
	}
	if !foundDeleted {
		t.Fatalf("expected doc-batch-c tombstone in sync pull response, got %+v", pullBody.Documents)
	}
}

func TestSyncPushRejectsOversizedBody(t *testing.T) {
	handler, cleanup := newTestServer(t)
	defer cleanup()

	token := registerAndGetToken(t, handler, "oversize@rowe.app")

	// Build a payload slightly larger than the 10 MiB MaxBytesReader limit
	huge := `{"documents":[{"id":"huge","payloadJson":"` + strings.Repeat("A", 11*1024*1024) + `"}]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewBufferString(huge))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest && rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 400/413 for oversized push payload, got %d", rec.Code)
	}
}

func TestEventHubMultiDocBroadcastAndBackpressure(t *testing.T) {
	hub := httpapi.NewEventHub()
	slowCh, unsubSlow := hub.Subscribe("user-1")
	defer unsubSlow()
	fastCh, unsubFast := hub.Subscribe("user-1")
	defer unsubFast()

	// Saturate the 64-slot buffer without reading from slowCh — Publish MUST NOT block
	done := make(chan struct{})
	go func() {
		for i := 0; i < 120; i++ {
			hub.Publish("user-1", httpapi.SyncEvent{
				Type:       "doc.updated",
				DocID:      "",
				ServerTime: int64(i + 1),
			})
		}
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatalf("EventHub.Publish blocked on full subscriber channel")
	}

	// Fast subscriber received events with empty DocID
	select {
	case evt := <-fastCh:
		if evt.Type != "doc.updated" || evt.DocID != "" {
			t.Fatalf("unexpected event: %+v", evt)
		}
	default:
		t.Fatalf("expected event on fast subscriber channel")
	}
	_ = slowCh
}

func TestRateLimiterBlocksBurstAndAllowsNormalTraffic(t *testing.T) {
	rl := middleware.NewRateLimiter(3)
	okHandler := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	for i := 0; i < 3; i++ {
		req := httptest.NewRequest(http.MethodGet, "/test", nil)
		req.RemoteAddr = "198.51.100.42:12345"
		rec := httptest.NewRecorder()
		okHandler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("request %d expected 200, got %d", i+1, rec.Code)
		}
	}

	// 4th request within same window must return 429 Too Many Requests
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	req.RemoteAddr = "198.51.100.42:12345"
	rec := httptest.NewRecorder()
	okHandler.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 on 4th request, got %d", rec.Code)
	}
}

func TestSQLiteUpsertDocumentsBatchAtomicAndExpiredRefreshCleanup(t *testing.T) {
	st, err := store.NewSQLiteStore(":memory:")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer func() { _ = st.Close() }()

	ctx := context.Background()
	user := &model.User{
		ID:           "u-atomic",
		Email:        "atomic@rowe.app",
		PasswordHash: "hash",
		DisplayName:  "Atomic",
		CreatedAt:    time.Now().UTC(),
	}
	if err := st.CreateUser(ctx, user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	now := time.Now().UTC()
	docs := []model.SyncDocument{
		{ID: "d1", UserID: user.ID, SpaceID: "s1", Title: "One", PayloadJSON: "[]", UpdatedAt: now},
		{ID: "d2", UserID: user.ID, SpaceID: "s1", Title: "Two", PayloadJSON: "[]", UpdatedAt: now},
	}
	saved, err := st.UpsertDocumentsBatch(ctx, docs)
	if err != nil {
		t.Fatalf("batch upsert failed: %v", err)
	}
	if len(saved) != 2 {
		t.Fatalf("expected 2 saved docs, got %d", len(saved))
	}

	// Verify expired refresh sessions are pruned when creating a new refresh session
	expired := &model.RefreshSession{
		ID:        "sess-expired",
		TokenHash: "expired-hash",
		UserID:    user.ID,
		Device:    "OldPhone",
		ExpiresAt: time.Now().UTC().Add(-2 * time.Hour),
		CreatedAt: time.Now().UTC().Add(-48 * time.Hour),
	}
	if err := st.CreateRefreshSession(ctx, expired); err != nil {
		t.Fatalf("save expired session: %v", err)
	}
	fresh := &model.RefreshSession{
		ID:        "sess-fresh",
		TokenHash: "fresh-hash",
		UserID:    user.ID,
		Device:    "NewMac",
		ExpiresAt: time.Now().UTC().Add(24 * time.Hour),
		CreatedAt: time.Now().UTC(),
	}
	if err := st.CreateRefreshSession(ctx, fresh); err != nil {
		t.Fatalf("save fresh session: %v", err)
	}

	if _, err := st.GetRefreshSessionByHash(ctx, "expired-hash"); err == nil {
		t.Fatalf("expected expired refresh session to be pruned")
	}
	if _, err := st.GetRefreshSessionByHash(ctx, "fresh-hash"); err != nil {
		t.Fatalf("expected fresh refresh session to remain valid: %v", err)
	}
}

// Keep unused import check clean
var _ = config.Config{}
