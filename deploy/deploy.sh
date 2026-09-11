#!/usr/bin/env bash
# The usual update on the server: pull main, rebuild only the API, reload Caddy's config.
#   ssh verspaetomat /opt/verspaetomat/deploy/deploy.sh
set -euo pipefail
cd "$(dirname "$0")"
git -C .. pull -q --ff-only
git -C .. log --oneline -1
docker compose up -d --build api 2>&1 | grep -E "Built|Started|Running|error" || true
# Caddy neu anlegen, falls sich Mount oder Domain geändert haben (die Website hängt als
# ../site/dist:/srv/site drin); sonst ist das hier ein no-op.
docker compose up -d caddy 2>&1 | grep -E "Recreated|Started|error" || true
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile 2>&1 | grep -E "error|adapted" || true
sleep 3
docker compose ps --format '{{.Name}} {{.Status}}'
docker compose logs --tail 40 api 2>/dev/null | grep -E "migrat|push:|listening|ERROR|WARN" | tail -6 | cut -c1-160
curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 || docker compose exec api curl -sf http://127.0.0.1:8080/health
# Die Website wird nicht gebaut, nur ausgeliefert: sie kommt fertig aus dem Git (docs/31).
docker compose exec -T caddy test -f /srv/site/index.html && echo "site: eingehängt" || echo "site: /srv/site fehlt — liegt site/dist im Git?"
echo
