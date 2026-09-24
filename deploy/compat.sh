#!/usr/bin/env bash
# Does the app build that is out there still work against the backend on staging? Run on the Mac:
#   deploy/compat.sh                      # the newest production build (highest ios-<version>-<build> tag)
#   deploy/compat.sh ios-1.0.0-79         # a given one
#   SIM=<udid> deploy/compat.sh           # another simulator
#
# House rule: old app versions must keep working against the new backend. This checks it rather
# than hoping: the workflow E2E of that build — its own code, from its own tag, in a separate
# worktree — runs in the simulator against staging, which by then runs the backend about to be
# promoted. The E2E drives the world through Stellwerk, which staging allows and production refuses.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-$(git tag -l 'ios-[0-9]*' | sort -t- -k3,3n | tail -1)}"
SIM="${SIM:-3490B4AD-6C37-4C5C-89A8-DCD31452B681}"
API="${API:-https://api.staging.verspaetomat.de}"
WT="$(mktemp -d)/compat-$TAG"
LOG="${TMPDIR:-/tmp}/compat-$TAG.log"

main() {
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "no tag $TAG" >&2; exit 1; }
  local token
  token="$(ssh verspaetomat-staging "grep -m1 '^ADMIN_TOKEN=' /opt/verspaetomat/deploy/.env" | cut -d= -f2)"
  echo "== $TAG (the app) against $API ($(curl -sf "$API/health" | sed -n 's/.*"commit":"\([^"]*\)".*/\1/p'))"
  git worktree add -q --detach "$WT" "$TAG"
  trap 'git worktree remove --force "$WT" >/dev/null 2>&1 || true' EXIT
  (
    cd "$WT/app"
    flutter pub get >/dev/null
    flutter test integration_test/workflow_test.dart -d "$SIM" \
      --dart-define=API_URL="$API" --dart-define=BACKEND=local --dart-define=NO_LOCATION=1 \
      --dart-define=E2E=true --dart-define=ADMIN_TOKEN="$token" --dart-define=INITIAL_ROUTE=/home >"$LOG" 2>&1 || true
    grep -E "^[0-9:]+ \+[0-9]+.*(passed|failed)|EXCEPTION|Expected|Actual|Timed out|══" "$LOG" | tail -20
    echo "== full log: $LOG"
  )
}

main "$@"
