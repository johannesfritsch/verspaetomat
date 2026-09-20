#!/usr/bin/env bash
# The Swift unit tests, on a simulator this machine actually has (issue #40).
#
#   app/tools/swift-test.sh
#   SIM_DEST='platform=iOS Simulator,id=<udid>' app/tools/swift-test.sh
#
# `Runner.xcscheme` has carried a TestAction with the RunnerTests testable and `skipped = "NO"`
# since the project was made. Nothing was ever missing but an invocation — which is why
# `Geofence.swift` could document an assertion as "failing ever since, because nothing runs the
# Swift tests". `release.sh` calls this before the archive, so every TestFlight build passes it.
#
# The destination is derived rather than named. A hardcoded `name=iPhone 16` does not resolve once
# a newer runtime is installed (this machine has iOS 26.5, whose iPhone is the 17), and the failure
# looks like a broken test run rather than a missing device.
set -euo pipefail
cd "$(dirname "$0")/.."

# `flutter test integration_test/…` leaves the iOS build configured for *that* run: its generated
# `listener.dart` lives in a temp directory that is deleted when it finishes, and the next
# xcodebuild picks the stale path up through the Run Script phase and dies with
# „Target kernel_snapshot_program failed" — which looks like a broken test suite and is not one.
# One cheap regeneration is worth more than the note it would otherwise take to explain.
flutter build ios --config-only --simulator >/dev/null 2>&1 || true

if [ -z "${SIM_DEST:-}" ]; then
  pick=$(xcrun simctl list -j devices available | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else None
found = []
for runtime, listed in devices.items():
    v = version(runtime)
    if v is None:
        continue
    for device in listed:
        if "iPhone" in device["name"]:
            # Newest runtime, and within it the plainest iPhone: shortest name, then alphabetical.
            # A Pro Max boots and runs the same tests more slowly, and picking by chance makes the
            # run report a different device every time for no reason.
            found.append((v, -len(device["name"]), device["name"], device["udid"]))
if not found:
    sys.exit("no iPhone simulator is available; install one in Xcode > Settings > Components")
best = max(found)
print(best[3] + " " + best[2])
')
  SIM_DEST="platform=iOS Simulator,id=${pick%% *}"
  echo "== ${pick#* } ($SIM_DEST)"
fi

echo "== swift tests"
# xcodebuild prints a failing test's *name* and nothing else — the assertion message lives only in
# the result bundle. A release gate that aborts without saying why is a gate people learn to
# distrust, so the bundle is kept and unpacked on failure.
RESULT="${TMPDIR:-/tmp}/verspaetomat-swift-tests.xcresult"
rm -rf "$RESULT"

set +e
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination "$SIM_DEST" \
  -only-testing:RunnerTests \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "== failures"
  xcrun xcresulttool get test-results tests --path "$RESULT" 2>/dev/null | python3 -c '
import json, sys
def walk(node, test=None):
    kind = node.get("nodeType")
    if kind == "Test Case":
        test = node.get("name", "?")
    if kind == "Failure Message":
        print("  " + (test or "?"))
        for line in node.get("name", "").splitlines():
            print("    " + line)
    for child in node.get("children", []):
        walk(child, test)
for root in json.load(sys.stdin).get("testNodes", []):
    walk(root)
' || echo "  (could not read $RESULT)"
  exit "$status"
fi

echo "== swift tests passed"
