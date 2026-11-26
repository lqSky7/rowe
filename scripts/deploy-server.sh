#!/usr/bin/env bash
# deploy-server.sh — remote deploy script executed on ubuntu@155.248.241.153
# Expects a gzipped tar stream of RoweServer/ on stdin (or extracts into /home/ubuntu/rowe-server).
set -euo pipefail

DEPLOY_DIR="/home/ubuntu/rowe-server"
mkdir -p "$DEPLOY_DIR"

TMP_TAR="$(mktemp /tmp/rowe-server.XXXXXX.tar.gz)"
trap 'rm -f "$TMP_TAR"' EXIT
cat > "$TMP_TAR"

tar -xzf "$TMP_TAR" -C "$DEPLOY_DIR"

cd "$DEPLOY_DIR"
if [[ ! -f .env ]]; then
  SECRET="$(openssl rand -hex 32)"
  cat > .env <<EOF
ROWE_ADDR=:8080
ROWE_DB_PATH=/data/rowe.db
ROWE_JWT_SECRET=${SECRET}
ROWE_CORS_ORIGINS=*
ROWE_RATE_LIMIT_PER_MIN=180
ROWE_AUTH_RATE_PER_MIN=20
EOF
  chmod 600 .env
fi

docker compose up -d --build --remove-orphans

for i in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:8090/healthz >/dev/null 2>&1; then
    echo "rowe-server healthy on :8090"
    exit 0
  fi
  sleep 1
done

echo "rowe-server failed health check" >&2
docker compose logs --tail=50 >&2
exit 1
