#!/usr/bin/env bash
# Runs the tour test and screenshots the simulator at each SHOT marker.
SIM="${SIM:-3490B4AD-6C37-4C5C-89A8-DCD31452B681}"
OUT="${OUT:-/tmp/verspaetomat-tour}"; mkdir -p "$OUT"
rm -f "$OUT"/*.png
cd "$(dirname "$0")/.."
flutter test integration_test/screenshot_tour_test.dart -d $SIM --dart-define=NO_LOCATION=1 --dart-define=NO_ANIM=1 2>&1 | while IFS= read -r line; do
  case "$line" in
    *"SHOT "*) n="${line##*SHOT }"; n="${n%% *}"; sleep 0.5; xcrun simctl io $SIM screenshot "$OUT/$n.png" >/dev/null 2>&1; echo "shot $n";;
    *"All tests"*|*"Some tests"*|*"[E]"*|*Exception*) echo "$line";;
  esac
done
