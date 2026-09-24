#!/usr/bin/env bash
# Build, sign, export and upload an iOS build to TestFlight without an Xcode login.
#
#   app/tools/release.sh            # version from pubspec, build number = last uploaded build + 1
#   BUILD=42 app/tools/release.sh   # explicit build number
# Uploaded builds are tagged ios-<version>-<build>; the next build number comes from the highest
# such tag (any version), so numbers stay sequential across versions, as App Store Connect wants.
#   DRY=1 app/tools/release.sh      # everything except the upload
#   STAGE=staging app/tools/release.sh   # the staging app: its own bundle id, name, icon, server
#
# Two apps in App Store Connect, team S4NEUU3775 since 24 September 2026: „Verspätomat"
# (de.verspaetomat.app, production) and „Verspätomat Staging" (de.verspaetomat.staging.app,
# internal TestFlight only). They install side by side
# and keep separate keychains, so an account on one server never meets the other. Each has its own
# build numbers and tags: ios-<version>-<build> and ios-staging-<version>-<build>.
#
# Needs an App Store Connect API key (App Store Connect → Users and Access → Integrations →
# App Store Connect API → Team Keys; role App Manager):
#   ~/.config/verspaetomat/release.env            ASC_KEY_ID=…  ASC_ISSUER_ID=…
#   ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8   (altool's default lookup path)
# Signing is automatic with cloud-managed certificates via that key, so no Apple ID has to be
# signed in to Xcode on this machine. Team and bundle id come from the Xcode project.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="$HOME/.config/verspaetomat/release.env"
[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE (ASC_KEY_ID=…, ASC_ISSUER_ID=…)"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[[ -f "$KEY" ]] || { echo "missing $KEY"; exit 1; }

STAGE="${STAGE:-production}"
case "$STAGE" in
  production)
    API_URL="${API_URL:-https://api.verspaetomat.de}"; SITE_URL="${SITE_URL:-https://verspaetomat.de}"
    TAG_PREFIX="ios-"; APP_SETTINGS=() ;;
  staging)
    API_URL="${API_URL:-https://api.staging.verspaetomat.de}"; SITE_URL="${SITE_URL:-https://staging.verspaetomat.de}"
    TAG_PREFIX="ios-staging-"
    # Only the app target reads these three (project.pbxproj); overriding PRODUCT_BUNDLE_IDENTIFIER
    # itself would rename every embedded framework too, which App Store Connect rejects.
    APP_SETTINGS=(VERSPAETOMAT_BUNDLE_ID=de.verspaetomat.staging.app "VERSPAETOMAT_DISPLAY_NAME=Verspätomat β" VERSPAETOMAT_APPICON=AppIconStaging) ;;
  *) echo "STAGE=$STAGE: production or staging"; exit 1 ;;
esac
VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)"
# `ios-[0-9]*`, not `ios-*`: the staging tags start with ios- too, and their numbers are their own.
if [[ "$STAGE" == staging ]]; then TAG_GLOB='ios-staging-*'; else TAG_GLOB='ios-[0-9]*'; fi
LAST="$(git tag -l "$TAG_GLOB" | sed -n 's/^.*-\([0-9]*\)$/\1/p' | sort -n | tail -1)"
BUILD="${BUILD:-$(( ${LAST:-0} + 1 ))}"
ARCHIVE="build/ios/archive/Runner.xcarchive"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "== Verspätomat $VERSION ($BUILD) · $STAGE → $API_URL"

# Before the archive, not after the upload (issue #40). The Swift unit tests have existed since
# docs/30 and nothing ever ran them, which is how `Geofence.swift` came to document an assertion
# as "failing ever since". This repo has no CI to hang them on — it deploys by `git push` plus
# `ssh verspaetomat .../deploy.sh` — so `release.sh` is the one gate every TestFlight build passes
# through. Deliberately no SKIP_TESTS.
#
# And before the `--config-only` below, not after: `swift-test.sh` builds for the simulator, which
# rewrites `Generated.xcconfig` — including the build number, back to pubspec's. Running it after
# the line below silently archived build 1 instead of build 66, which App Store Connect rejected
# as a duplicate. The archive must be the last thing to touch that file.
tools/swift-test.sh

flutter build ios --release --config-only --build-name="$VERSION" --build-number="$BUILD" \
  --dart-define=API_URL="$API_URL" --dart-define=SITE_URL="$SITE_URL" --dart-define=BACKEND=local \
  --dart-define=APP_VERSION="$VERSION ($BUILD)" --dart-define=STAGE="${STAGE/production/}" >/dev/null

echo "== archive"
rm -rf "$ARCHIVE"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" archive "${AUTH[@]}" ${APP_SETTINGS[@]+"${APP_SETTINGS[@]}"} -quiet

echo "== export"
rm -rf build/ios/ipa
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist tools/ExportOptions.plist \
  -exportPath build/ios/ipa "${AUTH[@]}" -quiet
IPA="$(ls build/ios/ipa/*.ipa)"
plutil -p "$ARCHIVE/Products/Applications/Runner.app/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleDisplayName|CFBundleShortVersionString|CFBundleVersion"|MinimumOSVersion' | sed 's/^ */   /'
ls -la "$IPA" | awk '{print "   " $5 " bytes  " $9}'

if [[ "${DRY:-0}" == "1" ]]; then echo "== dry run, not uploading"; exit 0; fi

echo "== upload"
UPLOAD_LOG="$(mktemp)"
if ! xcrun altool --upload-app --type ios --file "$IPA" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" >"$UPLOAD_LOG" 2>&1; then
  grep -vE "^\s*$" "$UPLOAD_LOG" | tail -8
  echo "== UPLOAD FAILED: build $BUILD not tagged"
  exit 1
fi
grep -E "Transferred|No errors|UPLOAD" "$UPLOAD_LOG" | tail -2
git tag -f "$TAG_PREFIX$VERSION-$BUILD" >/dev/null && git push -q --force origin "$TAG_PREFIX$VERSION-$BUILD"
echo "== done: build $BUILD uploaded and tagged; App Store Connect processes it in 10 to 30 min, then TestFlight"
