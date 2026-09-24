#!/usr/bin/env bash
# Promote what runs on staging to production. Run on the Mac:
#   deploy/promote.sh                 # the commit staging runs now
#   deploy/promote.sh <commit>        # a given one; staging must run exactly it
#   SKIP_COMPAT=1 deploy/promote.sh   # without the old-app check (say why in the commit or issue)
#
# Production only ever gets a commit that staging has run. In order:
#   1. staging is healthy and runs that commit (/health reports it);
#   2. the commit is on main, and production can fast-forward to it;
#   3. the last production app build still works against it (deploy/compat.sh);
#   4. the `production` branch moves to it, and the production server deploys: website and backend;
#   5. production reports the same commit.
# The production app comes after, from the same commit (the shipping order: website, backend,
# then TestFlight) — the script prints the command.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGING_API="https://api.staging.verspaetomat.de"
PROD_API="https://api.verspaetomat.de"

commit_of() { curl -sf "$1/health" | sed -n 's/.*"commit":"\([^"]*\)".*/\1/p'; }

main() {
  git fetch -q origin
  local running want
  running="$(commit_of "$STAGING_API")"
  [[ -n "$running" && "$running" != unknown ]] || { echo "staging is not healthy or does not say its commit" >&2; exit 1; }
  want="$(git rev-parse --verify "${1:-$running}^{commit}")"
  [[ "$want" == "$running"* ]] || { echo "staging runs $running, not ${want:0:12}: deploy it there first" >&2; exit 1; }
  git merge-base --is-ancestor "$want" origin/main || { echo "${want:0:12} is not on main" >&2; exit 1; }
  git merge-base --is-ancestor origin/production "$want" || { echo "production cannot fast-forward to ${want:0:12}" >&2; exit 1; }

  echo "== promoting ${want:0:12}: $(git log -1 --format=%s "$want")"
  git log --oneline origin/production.."$want" | sed 's/^/   /'
  if git diff --name-only origin/production "$want" -- backend/migrations | grep -q .; then
    echo "   with migrations: $(git diff --name-only origin/production "$want" -- backend/migrations | xargs -n1 basename | tr '\n' ' ')"
  fi

  if [[ "${SKIP_COMPAT:-0}" != 1 ]]; then
    deploy/compat.sh
    read -r -p "== old app build against staging: did it pass? [y/N] " ok
    [[ "$ok" == y ]] || { echo "stopped before production" >&2; exit 1; }
  fi

  git push -q origin "$want:refs/heads/production"
  ssh verspaetomat /opt/verspaetomat/deploy/deploy.sh
  local live
  live="$(commit_of "$PROD_API")"
  [[ "$want" == "$live"* ]] || { echo "production reports ${live:-nothing}, expected ${want:0:12}" >&2; exit 1; }
  echo "== production runs ${want:0:12}. The app, from the same commit:"
  echo "   git switch --detach ${want:0:12} && app/tools/release.sh && git switch -"
}

main "$@"
