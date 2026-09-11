#!/usr/bin/env bash
# The usual update on the server: pull main, rebuild only the API, reload Caddy's config.
#   ssh verspaetomat /opt/verspaetomat/deploy/deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

# Everything lives in a function on purpose. `git pull` below can rewrite this very file, and
# bash reads a script as it goes: on 11 September 2026 a changed deploy.sh made the running one
# continue at the old byte offset in the new text and silently skip its last three lines — the
# website was mounted nowhere and nobody was told. A function body is parsed before any of it
# runs, so the version that started is the version that finishes.
main() {
  git -C .. pull -q --ff-only
  git -C .. log --oneline -1

  docker compose up -d --build api 2>&1 | grep -E "Built|Started|Running|error" || true
  # Recreate Caddy when its mounts or domains changed (the website hangs in as
  # ../site/dist:/srv/site); a no-op otherwise.
  docker compose up -d caddy 2>&1 | grep -E "Recreated|Started|error" || true
  docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile 2>&1 | grep -E "error|adapted" || true
  sleep 3

  docker compose ps --format '{{.Name}} {{.Status}}'
  docker compose logs --tail 40 api 2>/dev/null | grep -E "migrat|push:|listening|ERROR|WARN" | tail -6 | cut -c1-160
  curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 || docker compose exec api curl -sf http://127.0.0.1:8080/health
  echo   # /health endet ohne Zeilenumbruch, sonst klebt die nächste Zeile daran
  # The website is not built here, only served: it comes ready from git (docs/31 §6).
  if docker compose exec -T caddy test -f /srv/site/index.html 2>/dev/null; then
    echo "site: $(docker compose exec -T caddy sh -c 'ls /srv/site | wc -l' | tr -d ' \r') Einträge in /srv/site"
  else
    echo "site: /srv/site fehlt — liegt site/dist im Git, und wurde caddy neu angelegt?"
  fi
  echo
}

main "$@"
