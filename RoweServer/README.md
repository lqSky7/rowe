# RoweServer

Clean, modular, zero-dependency Go backend for **Rowe** (Auth, Delta Sync, and Zero-Knowledge PIN-Locked Notes).

## Architecture
- **Language**: Go (stdlib HTTP router, PBKDF2-HMAC-SHA256 password hashing, HS256 JWTs, rotating refresh tokens)
- **Database**: SQLite in WAL mode via `internal/store.Store` interface (swap to PostgreSQL later by implementing `Store`)
- **Zero-Knowledge Locked Notes**:
  - Client generates a random 256-bit **Note Vault Key (NVK)** and wraps it locally using a **PBKDF2-HMAC-SHA256** (210,000 iterations) key derived from the user's 4- or 6-digit PIN + random salt.
  - Server stores only the encrypted `vault_keys` envelope (`PUT /api/v1/vault`) and opaque AES-256-GCM `encrypted_payload` ciphertext for locked documents (plaintext `payload_json` is stripped at the store layer).
  - Any of the user's signed-in devices fetches the wrapped vault envelope + encrypted notes and unlocks them locally with the same PIN.

## Endpoints
- `GET /healthz`
- `POST /api/v1/auth/register` — create account
- `POST /api/v1/auth/login` — sign in (returns access JWT, rotating refresh token, user, and vault envelope)
- `POST /api/v1/auth/refresh` — rotate refresh token
- `POST /api/v1/auth/logout` — revoke refresh token
- `GET /api/v1/auth/me` — current user & vault envelope
- `GET /api/v1/vault` / `PUT /api/v1/vault` — fetch or update PIN-wrapped vault key envelope
- `GET /api/v1/sync/pull?since=<unix_ms>` — delta pull
- `POST /api/v1/sync/push` — batch upsert documents
- `GET /api/v1/documents/{id}` / `DELETE /api/v1/documents/{id}`

## Run Locally
```bash
export ROWE_JWT_SECRET="$(openssl rand -hex 32)"
go run ./cmd/server
```

## Run Tests
```bash
go test -v ./...
```
