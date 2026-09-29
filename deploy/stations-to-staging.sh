#!/usr/bin/env bash
# Copy production's station table to staging. Run on the Mac, after every `stellwerk --prod
# stations import`, and after `reset-staging.sh`:
#   deploy/stations-to-staging.sh
#
# Station ids are handed out by the database that imports them, in the order it meets the stops,
# so two databases that import the same feed number it differently — measured 24 September 2026:
# every id shifted by one. The app carries production's extract, so a staging app would send
# production's ids to a server that means other stations by them. Production is the one place
# ids are made; staging takes its copy and never imports on its own.
#
# Only public data crosses: the station tables and the station premises from OSM (#64), nothing
# that names a person.
set -euo pipefail

PROD="${PROD:-verspaetomat}"
STAGING="${STAGING:-verspaetomat-staging}"
TABLES=(-t stations -t station_sources -t station_imports)

main() {
  if ! ssh "$STAGING" "grep -qx 'ENVIRONMENT=staging' /opt/verspaetomat/deploy/.env"; then
    echo "refused: $STAGING does not say ENVIRONMENT=staging" >&2
    exit 1
  fi
  local truncate="stations, station_sources, station_imports"
  # The premises (migration 0043) cross once production has the table. Staging always has it
  # first (it runs main), and the truncate below empties it either way: premises keyed to the
  # ids being replaced mean nothing.
  if ssh "$PROD" "cd /opt/verspaetomat/deploy && docker compose exec -T db psql -At -U verspaetomat -d verspaetomat -c \"select to_regclass('station_outlines') is not null\"" | grep -qx t; then
    TABLES+=(-t station_outlines)
  fi
  truncate+=", station_outlines"
  echo "== production → staging: ${TABLES[*]//-t /}"
  ssh "$PROD" "cd /opt/verspaetomat/deploy && docker compose exec -T db pg_dump -U verspaetomat -d verspaetomat --data-only ${TABLES[*]}" \
    | ssh "$STAGING" "cd /opt/verspaetomat/deploy && docker compose exec -T db psql -q -U verspaetomat -d verspaetomat -v ON_ERROR_STOP=1 -1 \
        -c 'truncate $truncate' -f -" >/dev/null
  # The API holds the table in memory; a restart reads the copy.
  ssh "$STAGING" "cd /opt/verspaetomat/deploy && docker compose restart api >/dev/null 2>&1"
  sleep 6
  ssh "$STAGING" "cd /opt/verspaetomat/deploy && docker compose exec -T db psql -At -U verspaetomat -d verspaetomat -c \
    \"select count(*) || ' stations, highest id ' || max(id) || ', ' || (select count(*) from station_outlines) || ' premises' from stations\""
}

main "$@"
