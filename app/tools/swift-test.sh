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
# `-quiet` swallows the `** TEST SUCCEEDED **` banner, so the exit status is the signal and the
# line below is the one a human reads. `set -e` means nothing after a failure gets printed.
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination "$SIM_DEST" \
  -only-testing:RunnerTests \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

echo "== swift tests passed"
