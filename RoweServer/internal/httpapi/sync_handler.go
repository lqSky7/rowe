package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"rowe-server/internal/middleware"
	"rowe-server/internal/model"
	"rowe-server/internal/store"
)

type SyncHandler struct {
	store store.Store
}

func NewSyncHandler(st store.Store) *SyncHandler {
	return &SyncHandler{store: st}
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

// Push upserts a batch of documents, enforcing zero-knowledge rules on locked notes.
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

	writeJSON(w, http.StatusOK, map[string]any{
		"serverTime": time.Now().UTC().UnixMilli(),
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
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
