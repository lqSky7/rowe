package store

import (
	"context"
	"errors"
	"time"

	"rowe-server/internal/model"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrAlreadyExists = errors.New("already exists")
	ErrConflict      = errors.New("version conflict")
)

// Store defines the persistence contract for RoweServer.
// Implementing this interface allows swapping SQLite for PostgreSQL cleanly.
type Store interface {
	Close() error

	// Users & Auth
	CreateUser(ctx context.Context, user *model.User) error
	GetUserByEmail(ctx context.Context, email string) (*model.User, error)
	GetUserByID(ctx context.Context, id string) (*model.User, error)
	UpdateUserPassword(ctx context.Context, userID, passwordHash string) error
	UpdateUserProfile(ctx context.Context, userID, displayName string) error
	UpdateUserAvatar(ctx context.Context, userID, avatarBase64, avatarMime string) error

	// Refresh Sessions
	CreateRefreshSession(ctx context.Context, session *model.RefreshSession) error
	GetRefreshSessionByHash(ctx context.Context, tokenHash string) (*model.RefreshSession, error)
	DeleteRefreshSessionByHash(ctx context.Context, tokenHash string) error
	DeleteAllUserSessions(ctx context.Context, userID string) error

	// Zero-Knowledge Vault Key Envelope
	UpsertVaultKey(ctx context.Context, env *model.VaultKeyEnvelope) error
	GetVaultKey(ctx context.Context, userID string) (*model.VaultKeyEnvelope, error)

	// Documents & Delta Sync
	UpsertDocument(ctx context.Context, doc *model.SyncDocument) (*model.SyncDocument, error)
	ListDocumentsSince(ctx context.Context, userID string, since time.Time) ([]model.SyncDocument, error)
	GetDocument(ctx context.Context, userID, docID string) (*model.SyncDocument, error)
	DeleteDocument(ctx context.Context, userID, docID string) error
}
