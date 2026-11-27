package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"rowe-server/internal/model"
)

type SQLiteStore struct {
	db *sqliteDB
}

func NewSQLiteStore(path string) (*SQLiteStore, error) {
	db, err := openSQLite(path)
	if err != nil {
		return nil, err
	}
	s := &SQLiteStore{db: db}
	if err := s.migrate(); err != nil {
		_ = db.close()
		return nil, err
	}
	return s, nil
}

func (s *SQLiteStore) Close() error {
	return s.db.close()
}

func (s *SQLiteStore) migrate() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id TEXT PRIMARY KEY,
			email TEXT NOT NULL UNIQUE,
			display_name TEXT NOT NULL DEFAULT '',
			avatar_base64 TEXT NOT NULL DEFAULT '',
			avatar_mime TEXT NOT NULL DEFAULT '',
			password_hash TEXT NOT NULL,
			created_at INTEGER NOT NULL,
			updated_at INTEGER NOT NULL
		);`,
		`CREATE TABLE IF NOT EXISTS refresh_sessions (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			token_hash TEXT NOT NULL UNIQUE,
			device TEXT NOT NULL DEFAULT '',
			expires_at INTEGER NOT NULL,
			created_at INTEGER NOT NULL
		);`,
		`CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_sessions(user_id);`,
		`CREATE TABLE IF NOT EXISTS vault_keys (
			user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
			wrapped_key TEXT NOT NULL,
			salt TEXT NOT NULL,
			nonce TEXT NOT NULL DEFAULT '',
			kdf_iterations INTEGER NOT NULL,
			pin_length INTEGER NOT NULL DEFAULT 6,
			version INTEGER NOT NULL DEFAULT 1,
			updated_at INTEGER NOT NULL
		);`,
		`CREATE TABLE IF NOT EXISTS documents (
			id TEXT NOT NULL,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			space_id TEXT NOT NULL,
			folder_id TEXT NOT NULL DEFAULT '',
			title TEXT NOT NULL DEFAULT '',
			is_locked INTEGER NOT NULL DEFAULT 0,
			payload_json TEXT NOT NULL DEFAULT '',
			encrypted_payload TEXT NOT NULL DEFAULT '',
			is_starred INTEGER NOT NULL DEFAULT 0,
			is_trashed INTEGER NOT NULL DEFAULT 0,
			version INTEGER NOT NULL DEFAULT 1,
			updated_at INTEGER NOT NULL,
			deleted_at INTEGER,
			PRIMARY KEY (user_id, id)
		);`,
		`CREATE INDEX IF NOT EXISTS idx_docs_user_updated ON documents(user_id, updated_at);`,
		`CREATE TABLE IF NOT EXISTS focus_states (
			user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
			state_json TEXT NOT NULL DEFAULT '',
			updated_at INTEGER NOT NULL
		);`,
	}
	for _, stmt := range stmts {
		if err := s.db.exec(stmt); err != nil {
			return err
		}
	}
	_ = s.db.exec(`ALTER TABLE users ADD COLUMN avatar_base64 TEXT NOT NULL DEFAULT ''`)
	_ = s.db.exec(`ALTER TABLE users ADD COLUMN avatar_mime TEXT NOT NULL DEFAULT ''`)
	_ = s.db.exec(`DELETE FROM refresh_sessions WHERE expires_at < ?`, time.Now().UTC().UnixMilli())
	return nil
}

// MARK: - Users

func (s *SQLiteStore) CreateUser(_ context.Context, u *model.User) error {
	email := strings.ToLower(strings.TrimSpace(u.Email))
	now := time.Now().UTC()
	u.Email = email
	if u.CreatedAt.IsZero() {
		u.CreatedAt = now
	}
	u.UpdatedAt = now
	err := s.db.exec(
		`INSERT INTO users (id, email, display_name, password_hash, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		u.ID, u.Email, u.DisplayName, u.PasswordHash, u.CreatedAt.UnixMilli(), u.UpdatedAt.UnixMilli(),
	)
	if errors.Is(err, ErrAlreadyExists) {
		return ErrAlreadyExists
	}
	return err
}

func (s *SQLiteStore) GetUserByEmail(_ context.Context, email string) (*model.User, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	var out *model.User
	err := s.db.queryRows(
		`SELECT id, email, display_name, avatar_base64, avatar_mime, password_hash, created_at, updated_at FROM users WHERE email = ? LIMIT 1`,
		[]any{email},
		func(cols []any) error {
			out = &model.User{
				ID:           asString(cols[0]),
				Email:        asString(cols[1]),
				DisplayName:  asString(cols[2]),
				AvatarBase64: asString(cols[3]),
				AvatarMime:   asString(cols[4]),
				PasswordHash: asString(cols[5]),
				CreatedAt:    time.UnixMilli(asInt64(cols[6])).UTC(),
				UpdatedAt:    time.UnixMilli(asInt64(cols[7])).UTC(),
			}
			return nil
		},
	)
	if err != nil {
		return nil, err
	}
	if out == nil {
		return nil, ErrNotFound
	}
	return out, nil
}

func (s *SQLiteStore) GetUserByID(_ context.Context, id string) (*model.User, error) {
	var out *model.User
	err := s.db.queryRows(
		`SELECT id, email, display_name, avatar_base64, avatar_mime, password_hash, created_at, updated_at FROM users WHERE id = ? LIMIT 1`,
		[]any{id},
		func(cols []any) error {
			out = &model.User{
				ID:           asString(cols[0]),
				Email:        asString(cols[1]),
				DisplayName:  asString(cols[2]),
				AvatarBase64: asString(cols[3]),
				AvatarMime:   asString(cols[4]),
				PasswordHash: asString(cols[5]),
				CreatedAt:    time.UnixMilli(asInt64(cols[6])).UTC(),
				UpdatedAt:    time.UnixMilli(asInt64(cols[7])).UTC(),
			}
			return nil
		},
	)
	if err != nil {
		return nil, err
	}
	if out == nil {
		return nil, ErrNotFound
	}
	return out, nil
}

func (s *SQLiteStore) UpdateUserPassword(_ context.Context, userID, passwordHash string) error {
	return s.db.exec(
		`UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?`,
		passwordHash, time.Now().UTC().UnixMilli(), userID,
	)
}

func (s *SQLiteStore) UpdateUserProfile(_ context.Context, userID, displayName string) error {
	return s.db.exec(
		`UPDATE users SET display_name = ?, updated_at = ? WHERE id = ?`,
		displayName, time.Now().UTC().UnixMilli(), userID,
	)
}

func (s *SQLiteStore) UpdateUserAvatar(_ context.Context, userID, avatarBase64, avatarMime string) error {
	return s.db.exec(
		`UPDATE users SET avatar_base64 = ?, avatar_mime = ?, updated_at = ? WHERE id = ?`,
		avatarBase64, avatarMime, time.Now().UTC().UnixMilli(), userID,
	)
}

// MARK: - Refresh Sessions

func (s *SQLiteStore) CreateRefreshSession(_ context.Context, sess *model.RefreshSession) error {
	// Prune expired sessions so refresh_sessions never grows unbounded.
	_ = s.db.exec(`DELETE FROM refresh_sessions WHERE expires_at < ?`, time.Now().UTC().UnixMilli())
	return s.db.exec(
		`INSERT INTO refresh_sessions (id, user_id, token_hash, device, expires_at, created_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		sess.ID, sess.UserID, sess.TokenHash, sess.Device, sess.ExpiresAt.UnixMilli(), sess.CreatedAt.UnixMilli(),
	)
}

func (s *SQLiteStore) GetRefreshSessionByHash(_ context.Context, tokenHash string) (*model.RefreshSession, error) {
	var out *model.RefreshSession
	err := s.db.queryRows(
		`SELECT id, user_id, token_hash, device, expires_at, created_at FROM refresh_sessions WHERE token_hash = ? LIMIT 1`,
		[]any{tokenHash},
		func(cols []any) error {
			out = &model.RefreshSession{
				ID:        asString(cols[0]),
				UserID:    asString(cols[1]),
				TokenHash: asString(cols[2]),
				Device:    asString(cols[3]),
				ExpiresAt: time.UnixMilli(asInt64(cols[4])).UTC(),
				CreatedAt: time.UnixMilli(asInt64(cols[5])).UTC(),
			}
			return nil
		},
	)
	if err != nil {
		return nil, err
	}
	if out == nil {
		return nil, ErrNotFound
	}
	return out, nil
}

func (s *SQLiteStore) DeleteRefreshSessionByHash(_ context.Context, tokenHash string) error {
	return s.db.exec(`DELETE FROM refresh_sessions WHERE token_hash = ?`, tokenHash)
}

func (s *SQLiteStore) DeleteAllUserSessions(_ context.Context, userID string) error {
	return s.db.exec(`DELETE FROM refresh_sessions WHERE user_id = ?`, userID)
}

// MARK: - Zero-Knowledge Vault Key Envelope

func (s *SQLiteStore) UpsertVaultKey(_ context.Context, env *model.VaultKeyEnvelope) error {
	now := time.Now().UTC()
	env.UpdatedAt = now
	if env.Version < 1 {
		env.Version = 1
	}
	return s.db.exec(
		`INSERT INTO vault_keys (user_id, wrapped_key, salt, nonce, kdf_iterations, pin_length, version, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(user_id) DO UPDATE SET
		   wrapped_key = excluded.wrapped_key,
		   salt = excluded.salt,
		   nonce = excluded.nonce,
		   kdf_iterations = excluded.kdf_iterations,
		   pin_length = excluded.pin_length,
		   version = vault_keys.version + 1,
		   updated_at = excluded.updated_at`,
		env.UserID, env.WrappedKey, env.Salt, env.Nonce, env.KDFIterations, env.PinLength, env.Version, now.UnixMilli(),
	)
}

func (s *SQLiteStore) GetVaultKey(_ context.Context, userID string) (*model.VaultKeyEnvelope, error) {
	var out *model.VaultKeyEnvelope
	err := s.db.queryRows(
		`SELECT user_id, wrapped_key, salt, nonce, kdf_iterations, pin_length, version, updated_at
		 FROM vault_keys WHERE user_id = ? LIMIT 1`,
		[]any{userID},
		func(cols []any) error {
			out = &model.VaultKeyEnvelope{
				UserID:        asString(cols[0]),
				WrappedKey:    asString(cols[1]),
				Salt:          asString(cols[2]),
				Nonce:         asString(cols[3]),
				KDFIterations: int(asInt64(cols[4])),
				PinLength:     int(asInt64(cols[5])),
				Version:       int(asInt64(cols[6])),
				UpdatedAt:     time.UnixMilli(asInt64(cols[7])).UTC(),
			}
			return nil
		},
	)
	if err != nil {
		return nil, err
	}
	if out == nil {
		return nil, ErrNotFound
	}
	return out, nil
}

// MARK: - Documents & Delta Sync

func (s *SQLiteStore) UpsertDocument(_ context.Context, doc *model.SyncDocument) (*model.SyncDocument, error) {
	now := time.Now().UTC()
	// Strict zero-knowledge invariant: locked notes must NEVER store plaintext payload_json.
	if doc.IsLocked {
		doc.PayloadJSON = ""
	}
	var deletedArg any = nil
	if doc.DeletedAt != nil {
		deletedArg = doc.DeletedAt.UTC().UnixMilli()
	}

	err := s.db.exec(
		`INSERT INTO documents (
			id, user_id, space_id, folder_id, title, is_locked,
			payload_json, encrypted_payload, is_starred, is_trashed,
			version, updated_at, deleted_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(user_id, id) DO UPDATE SET
			space_id = excluded.space_id,
			folder_id = excluded.folder_id,
			title = excluded.title,
			is_locked = excluded.is_locked,
			payload_json = excluded.payload_json,
			encrypted_payload = excluded.encrypted_payload,
			is_starred = excluded.is_starred,
			is_trashed = excluded.is_trashed,
			version = documents.version + 1,
			updated_at = excluded.updated_at,
			deleted_at = excluded.deleted_at`,
		doc.ID, doc.UserID, doc.SpaceID, doc.FolderID, doc.Title, doc.IsLocked,
		doc.PayloadJSON, doc.EncryptedPayload, doc.IsStarred, doc.IsTrashed,
		max64(1, doc.Version), now.UnixMilli(), deletedArg,
	)
	if err != nil {
		return nil, err
	}
	return s.GetDocument(context.Background(), doc.UserID, doc.ID)
}

// UpsertDocumentsBatch atomically upserts all documents in a single SQLite transaction.
func (s *SQLiteStore) UpsertDocumentsBatch(_ context.Context, docs []model.SyncDocument) ([]model.SyncDocument, error) {
	saved := make([]model.SyncDocument, 0, len(docs))
	if len(docs) == 0 {
		return saved, nil
	}
	nowMs := time.Now().UTC().UnixMilli()
	err := s.db.withTx(func() error {
		for i := range docs {
			doc := docs[i]
			if doc.IsLocked {
				doc.PayloadJSON = ""
			}
			var deletedArg any = nil
			if doc.DeletedAt != nil {
				deletedArg = doc.DeletedAt.UTC().UnixMilli()
			}
			if err := s.db.execLocked(
				`INSERT INTO documents (
					id, user_id, space_id, folder_id, title, is_locked,
					payload_json, encrypted_payload, is_starred, is_trashed,
					version, updated_at, deleted_at
				) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				ON CONFLICT(user_id, id) DO UPDATE SET
					space_id = excluded.space_id,
					folder_id = excluded.folder_id,
					title = excluded.title,
					is_locked = excluded.is_locked,
					payload_json = excluded.payload_json,
					encrypted_payload = excluded.encrypted_payload,
					is_starred = excluded.is_starred,
					is_trashed = excluded.is_trashed,
					version = documents.version + 1,
					updated_at = excluded.updated_at,
					deleted_at = excluded.deleted_at`,
				doc.ID, doc.UserID, doc.SpaceID, doc.FolderID, doc.Title, doc.IsLocked,
				doc.PayloadJSON, doc.EncryptedPayload, doc.IsStarred, doc.IsTrashed,
				max64(1, doc.Version), nowMs, deletedArg,
			); err != nil {
				return err
			}
			var out *model.SyncDocument
			if err := s.db.queryRowsLocked(
				`SELECT id, user_id, space_id, folder_id, title, is_locked,
				        payload_json, encrypted_payload, is_starred, is_trashed,
				        version, updated_at, deleted_at
				 FROM documents WHERE user_id = ? AND id = ? LIMIT 1`,
				[]any{doc.UserID, doc.ID},
				func(cols []any) error {
					d := scanDocument(cols)
					out = &d
					return nil
				},
			); err != nil {
				return err
			}
			if out != nil {
				saved = append(saved, *out)
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return saved, nil
}

func (s *SQLiteStore) GetDocument(_ context.Context, userID, docID string) (*model.SyncDocument, error) {
	var out *model.SyncDocument
	err := s.db.queryRows(
		`SELECT id, user_id, space_id, folder_id, title, is_locked,
		        payload_json, encrypted_payload, is_starred, is_trashed,
		        version, updated_at, deleted_at
		 FROM documents WHERE user_id = ? AND id = ? LIMIT 1`,
		[]any{userID, docID},
		func(cols []any) error {
			d := scanDocument(cols)
			out = &d
			return nil
		},
	)
	if err != nil {
		return nil, err
	}
	if out == nil {
		return nil, ErrNotFound
	}
	return out, nil
}

func (s *SQLiteStore) ListDocumentsSince(_ context.Context, userID string, since time.Time) ([]model.SyncDocument, error) {
	docs := make([]model.SyncDocument, 0)
	err := s.db.queryRows(
		`SELECT id, user_id, space_id, folder_id, title, is_locked,
		        payload_json, encrypted_payload, is_starred, is_trashed,
		        version, updated_at, deleted_at
		 FROM documents WHERE user_id = ? AND updated_at > ?
		 ORDER BY updated_at ASC`,
		[]any{userID, since.UTC().UnixMilli()},
		func(cols []any) error {
			docs = append(docs, scanDocument(cols))
			return nil
		},
	)
	return docs, err
}

func (s *SQLiteStore) DeleteDocument(_ context.Context, userID, docID string) error {
	now := time.Now().UTC().UnixMilli()
	return s.db.exec(
		`UPDATE documents SET deleted_at = ?, updated_at = ?, payload_json = '', encrypted_payload = '', version = version + 1
		 WHERE user_id = ? AND id = ?`,
		now, now, userID, docID,
	)
}

func scanDocument(cols []any) model.SyncDocument {
	doc := model.SyncDocument{
		ID:               asString(cols[0]),
		UserID:           asString(cols[1]),
		SpaceID:          asString(cols[2]),
		FolderID:         asString(cols[3]),
		Title:            asString(cols[4]),
		IsLocked:         asInt64(cols[5]) == 1,
		PayloadJSON:      asString(cols[6]),
		EncryptedPayload: asString(cols[7]),
		IsStarred:        asInt64(cols[8]) == 1,
		IsTrashed:        asInt64(cols[9]) == 1,
		Version:          asInt64(cols[10]),
		UpdatedAt:        time.UnixMilli(asInt64(cols[11])).UTC(),
	}
	if cols[12] != nil {
		t := time.UnixMilli(asInt64(cols[12])).UTC()
		doc.DeletedAt = &t
	}
	return doc
}

// MARK: - Adaptive Focus Behavioral State

func (s *SQLiteStore) GetFocusState(_ context.Context, userID string) (string, int64, error) {
	var stateJSON string
	var updatedAt int64
	var found bool
	err := s.db.queryRows(
		`SELECT state_json, updated_at FROM focus_states WHERE user_id = ? LIMIT 1`,
		[]any{userID},
		func(cols []any) error {
			stateJSON = asString(cols[0])
			updatedAt = asInt64(cols[1])
			found = true
			return nil
		},
	)
	if err != nil {
		return "", 0, err
	}
	if !found {
		return "", 0, ErrNotFound
	}
	return stateJSON, updatedAt, nil
}

func (s *SQLiteStore) UpsertFocusState(_ context.Context, userID, stateJSON string, updatedAt int64) (int64, error) {
	now := time.Now().UTC().UnixMilli()
	if updatedAt > now {
		now = updatedAt
	}
	err := s.db.exec(
		`INSERT INTO focus_states (user_id, state_json, updated_at)
		 VALUES (?, ?, ?)
		 ON CONFLICT(user_id) DO UPDATE SET
		   state_json = excluded.state_json,
		   updated_at = excluded.updated_at`,
		userID, stateJSON, now,
	)
	if err != nil {
		return 0, err
	}
	return now, nil
}

func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
