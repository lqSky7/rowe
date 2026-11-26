package model

import "time"

// User represents an authenticated Rowe account.
type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	DisplayName  string    `json:"displayName"`
	AvatarBase64 string    `json:"avatarBase64,omitempty"`
	AvatarMime   string    `json:"avatarMime,omitempty"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
	UpdatedAt    time.Time `json:"updatedAt"`
}

// RefreshSession tracks a revocable refresh token (stored as SHA-256 hash).
type RefreshSession struct {
	ID        string
	UserID    string
	TokenHash string
	Device    string
	ExpiresAt time.Time
	CreatedAt time.Time
}

// VaultKeyEnvelope stores the client-side PIN-wrapped 256-bit Note Vault Key (NVK).
// The server NEVER receives the user's PIN or the plaintext NVK; it only relays
// this encrypted envelope so the user can unlock notes across all their devices.
type VaultKeyEnvelope struct {
	UserID        string    `json:"userId,omitempty"`
	WrappedKey    string    `json:"wrappedKey"`    // Base64 AES-256-GCM(KEK, NVK)
	Salt          string    `json:"salt"`          // Base64 16-byte PBKDF2 salt
	Nonce         string    `json:"nonce"`         // Base64 12-byte GCM nonce (or empty if combined in WrappedKey)
	KDFIterations int       `json:"kdfIterations"` // e.g. 210000
	PinLength     int       `json:"pinLength"`     // 4 or 6
	Version       int       `json:"version"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

// SyncDocument is the server-side representation of a Rowe document.
// When IsLocked is true, PayloadJSON MUST be empty and EncryptedPayload holds
// opaque client-encrypted AES-256-GCM ciphertext so nobody with DB access can read it.
type SyncDocument struct {
	ID               string    `json:"id"`
	UserID           string    `json:"userId,omitempty"`
	SpaceID          string    `json:"spaceId"`
	FolderID         string    `json:"folderId,omitempty"`
	Title            string    `json:"title"`
	IsLocked         bool      `json:"isLocked"`
	PayloadJSON      string    `json:"payloadJson,omitempty"`
	EncryptedPayload string    `json:"encryptedPayload,omitempty"`
	IsStarred        bool      `json:"isStarred"`
	IsTrashed        bool      `json:"isTrashed"`
	Version          int64     `json:"version"`
	UpdatedAt        time.Time `json:"updatedAt"`
	DeletedAt        *time.Time `json:"deletedAt,omitempty"`
}
