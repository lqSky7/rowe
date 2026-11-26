package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"rowe-server/internal/middleware"
	"rowe-server/internal/model"
	"rowe-server/internal/store"
)

type SyncHandler struct {
	store store.Store
	hub   *EventHub
}

func NewSyncHandler(st store.Store, hub *EventHub) *SyncHandler {
	return &SyncHandler{store: st, hub: hub}
}

type syncPushRequest struct {
	Documents []model.SyncDocument `json:"documents"`
}

// Pull returns all documents updated after `since` (Unix milliseconds, default 0 = full sync).
func (h *SyncHandler) Pull(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	var since time.Time
	if raw := r.URL.Query().Get("since"); raw != "" {
		if ms, err := strconv.ParseInt(raw, 10, 64); err == nil && ms > 0 {
			since = time.UnixMilli(ms).UTC()
		}
	}

	docs, err := h.store.ListDocumentsSince(r.Context(), userID, since)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not pull documents")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"serverTime": time.Now().UTC().UnixMilli(),
		"documents":  docs,
	})
}

// Push upserts a batch of documents, enforcing zero-knowledge rules on locked notes,
// and notifies all connected SSE clients for this user immediately.
func (h *SyncHandler) Push(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	var req syncPushRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	saved := make([]model.SyncDocument, 0, len(req.Documents))
	for i := range req.Documents {
		doc := req.Documents[i]
		if doc.ID == "" {
			writeError(w, http.StatusBadRequest, "every document must have an id")
			return
		}
		if doc.IsLocked && doc.EncryptedPayload == "" {
			writeError(w, http.StatusBadRequest, "locked documents must include encryptedPayload")
			return
		}
		doc.UserID = userID
		if doc.IsLocked {
			// Enforce zero-knowledge: strip any accidental plaintext payload before persistence.
			doc.PayloadJSON = ""
		}
		out, err := h.store.UpsertDocument(r.Context(), &doc)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to sync document "+doc.ID)
			return
		}
		saved = append(saved, *out)
	}

	nowMs := time.Now().UTC().UnixMilli()
	if len(saved) > 0 && h.hub != nil {
		h.hub.Publish(userID, SyncEvent{
			Type:       "doc.updated",
			DocID:      saved[0].ID,
			ServerTime: nowMs,
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"serverTime": nowMs,
		"documents":  saved,
	})
}

func (h *SyncHandler) GetDocument(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	docID := r.PathValue("id")
	doc, err := h.store.GetDocument(r.Context(), userID, docID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, http.StatusNotFound, "document not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not load document")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"document": doc})
}

func (h *SyncHandler) DeleteDocument(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	docID := r.PathValue("id")
	if err := h.store.DeleteDocument(r.Context(), userID, docID); err != nil {
		writeError(w, http.StatusInternalServerError, "could not delete document")
		return
	}
	if h.hub != nil {
		h.hub.Publish(userID, SyncEvent{
			Type:       "doc.deleted",
			DocID:      docID,
			ServerTime: time.Now().UTC().UnixMilli(),
		})
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// Events streams real-time Server-Sent Events (SSE) whenever any of the user's devices
// pushes a task/document update or deletes a document.
func (h *SyncHandler) Events(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "streaming unsupported")
		return
	}

	// Disable the server's 30s WriteTimeout for this long-lived SSE connection.
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Time{})

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache, no-transform")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	_, _ = fmt.Fprint(w, ": connected\n\n")
	flusher.Flush()

	ch, unsub := h.hub.Subscribe(userID)
	defer unsub()

	ticker := time.NewTicker(25 * time.Second)
	defer ticker.Stop()

	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if _, err := fmt.Fprint(w, ": ping\n\n"); err != nil {
				return
			}
			flusher.Flush()
		case evt := <-ch:
			payload, err := json.Marshal(evt)
			if err != nil {
				continue
			}
			if _, err := fmt.Fprintf(w, "event: sync\ndata: %s\n\n", payload); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}
