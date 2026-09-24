#!/usr/bin/env bash
# Staging only: throw the database and the uploads away and start empty (fixtures seed again).
#   ssh verspaetomat-staging /opt/verspaetomat/deploy/reset-staging.sh
# Afterwards, from the Mac: `stellwerk --staging stations import` — a fresh database has no stations.
#
# Staging holds only made-up data, so this is the answer to anything that went wrong there: a
# migration edited after it ran, a world simulated into a corner. It refuses to run on a box whose
# .env does not say ENVIRONMENT=staging, because on production the same two volumes are everything.
set -euo pipefail
cd "$(dirname "$0")"

main() {
  if ! grep -qx 'ENVIRONMENT=staging' .env 2>/dev/null; then
    echo "refused: deploy/.env here does not say ENVIRONMENT=staging" >&2
    exit 1
  fi
  local project
  project="$(docker compose config --format json | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' | head -1)"
  echo "== resetting staging (compose project ${project})"
  docker compose stop api db
  docker compose rm -f api db
  docker volume rm "${project}_pgdata" "${project}_uploads"
  GIT_SHA="$(git -C .. rev-parse --short=12 HEAD)" docker compose up -d
  sleep 5
  docker compose ps --format '{{.Name}} {{.Status}}'
  echo "== empty. Next, on the Mac: stellwerk --staging stations import"
}

main "$@"
