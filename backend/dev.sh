#!/usr/bin/env bash
# One command to a running backend on a fresh machine with Homebrew Postgres.
set -euo pipefail
cd "$(dirname "$0")"

export DATABASE_URL="${DATABASE_URL:-postgres://localhost/verspaetomat}"
export RUST_LOG="${RUST_LOG:-info,tower_http=info,sqlx=warn}"

if ! pg_isready -q 2>/dev/null; then
  echo "starting postgresql@17"; brew services start postgresql@17 >/dev/null
  for _ in $(seq 1 20); do pg_isready -q && break; sleep 1; done
fi
createdb verspaetomat 2>/dev/null || true

if [[ "${1:-}" == "--reset" ]]; then
  echo "dropping and recreating verspaetomat"
  dropdb verspaetomat && createdb verspaetomat
fi

# Optional: SMTP_URL=smtps://user:pass@host:465  INBOUND_SECRET=…  BIND=0.0.0.0:8080 (for a phone on the LAN)
exec cargo run
