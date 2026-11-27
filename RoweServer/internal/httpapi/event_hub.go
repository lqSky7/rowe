package httpapi

import (
	"sync"
)

// SyncEvent is pushed over Server-Sent Events (SSE) to all connected devices of a user
// whenever any mutation occurs (task check, document edit, delete, vault/profile update).
type SyncEvent struct {
	Type       string `json:"type"`
	DocID      string `json:"docId,omitempty"`
	ServerTime int64  `json:"serverTime"`
}

// EventHub is a lightweight, zero-dependency in-memory pub/sub broker keyed by userID.
type EventHub struct {
	mu          sync.RWMutex
	subscribers map[string]map[chan SyncEvent]struct{}
}

func NewEventHub() *EventHub {
	return &EventHub{
		subscribers: make(map[string]map[chan SyncEvent]struct{}),
	}
}

func (h *EventHub) Subscribe(userID string) (chan SyncEvent, func()) {
	ch := make(chan SyncEvent, 64)
	h.mu.Lock()
	if h.subscribers[userID] == nil {
		h.subscribers[userID] = make(map[chan SyncEvent]struct{})
	}
	h.subscribers[userID][ch] = struct{}{}
	h.mu.Unlock()

	unsub := func() {
		h.mu.Lock()
		if set, ok := h.subscribers[userID]; ok {
			delete(set, ch)
			if len(set) == 0 {
				delete(h.subscribers, userID)
			}
		}
		h.mu.Unlock()
	}
	return ch, unsub
}

// Publish fans out an event to every active SSE stream for userID without blocking slow clients.
func (h *EventHub) Publish(userID string, evt SyncEvent) {
	if h == nil || userID == "" {
		return
	}
	h.mu.RLock()
	set := h.subscribers[userID]
	for ch := range set {
		select {
		case ch <- evt:
		default:
			// Slow consumer already has pending sync events; drop duplicate wakeup safely.
		}
	}
	h.mu.RUnlock()
}
