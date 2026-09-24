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
# Only public timetable data crosses: the three station tables, nothing that names a person.
set -euo pipefail

PROD="${PROD:-verspaetomat}"
STAGING="${STAGING:-verspaetomat-staging}"
TABLES=(-t stations -t station_sources -t station_imports)

main() {
  if ! ssh "$STAGING" "grep -qx 'ENVIRONMENT=staging' /opt/verspaetomat/deploy/.env"; then
    echo "refused: $STAGING does not say ENVIRONMENT=staging" >&2
    exit 1
  fi
  echo "== production → staging: stations, station_sources, station_imports"
  ssh "$PROD" "cd /opt/verspaetomat/deploy && docker compose exec -T db pg_dump -U verspaetomat -d verspaetomat --data-only ${TABLES[*]}" \
    | ssh "$STAGING" "cd /opt/verspaetomat/deploy && docker compose exec -T db psql -q -U verspaetomat -d verspaetomat -v ON_ERROR_STOP=1 -1 \
        -c 'truncate stations, station_sources, station_imports' -f -" >/dev/null
  # The API holds the table in memory; a restart reads the copy.
  ssh "$STAGING" "cd /opt/verspaetomat/deploy && docker compose restart api >/dev/null 2>&1"
  sleep 6
  ssh "$STAGING" "cd /opt/verspaetomat/deploy && docker compose exec -T db psql -At -U verspaetomat -d verspaetomat -c \
    \"select count(*) || ' stations, highest id ' || max(id) from stations\""
}

main "$@"
