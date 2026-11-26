# Rowe

A native Apple workspace (macOS + iOS) paired with a zero-dependency Go sync & zero-knowledge PIN-vault backend.

## Monorepo Layout

- `RoweApp/RoweCore/` — Shared Swift 6 package (models, CRDT/sync scheduler, AES-256-GCM zero-knowledge vault crypto, formula engine, `RoweBackendClient`, `WorkspaceStore`).
- `RoweApp/RoweMacOS/` — Native macOS SwiftUI + AppKit app (`RoweApp/install.sh`).
- `RoweApp/RoweIOS/` — Native iOS SwiftUI app (`RoweApp/RoweIOS/project.yml` via XcodeGen).
- `RoweApp/RoweShared/` — Shared Metal GlassGlow shaders and onboarding views.
- `RoweServer/` — Zero-dependency Go HTTP + SQLite WAL backend (`https://rowe.traverses.dpdns.org`).
- `altstore/apps.json` — FlareStore / AltStore / SideStore app source feed for iOS `.ipa` releases.

## Quick Build

### Backend (`RoweServer`)
```bash
cd RoweServer
go test ./...
docker compose up -d --build
```

### macOS App (`RoweApp`)
```bash
cd RoweApp
./install.sh --build-only
```

### iOS Unsigned IPA (FlareStore / AltStore)
```bash
./scripts/build-ipa.sh release
```

## CI/CD Workflows (Manual `workflow_dispatch`)

- **Deploy Backend** (`.github/workflows/deploy-backend.yml`): Runs Go tests and deploys `RoweServer` to production over SSH.
- **Release macOS App** (`.github/workflows/release-macos.yml`): Builds `Rowe.app`, packages `.zip` and `.dmg`, and publishes a GitHub Release.
- **Release iOS IPA** (`.github/workflows/release-ios.yml`): Builds `Rowe-<version>.ipa`, publishes a GitHub Release, and updates `altstore/apps.json` for FlareStore.
