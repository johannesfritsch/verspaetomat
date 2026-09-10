#!/usr/bin/env bash
# Build, sign, export and upload an iOS build to TestFlight without an Xcode login.
#
#   app/tools/release.sh            # version from pubspec, build number = commit count
#   BUILD=42 app/tools/release.sh   # explicit build number
#   DRY=1 app/tools/release.sh      # everything except the upload
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

API_URL="${API_URL:-https://api.verspaetomat.de}"
VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)"
BUILD="${BUILD:-$(git rev-list --count HEAD)}"
ARCHIVE="build/ios/archive/Runner.xcarchive"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "== Verspätomat $VERSION ($BUILD) → $API_URL"
flutter build ios --release --config-only --build-name="$VERSION" --build-number="$BUILD" \
  --dart-define=API_URL="$API_URL" --dart-define=BACKEND=local >/dev/null

echo "== archive"
rm -rf "$ARCHIVE"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" archive "${AUTH[@]}" -quiet

echo "== export"
rm -rf build/ios/ipa
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist tools/ExportOptions.plist \
  -exportPath build/ios/ipa "${AUTH[@]}" -quiet
IPA="$(ls build/ios/ipa/*.ipa)"
plutil -p "$ARCHIVE/Products/Applications/Runner.app/Info.plist" | grep -E 'CFBundleShortVersionString|CFBundleVersion"|MinimumOSVersion' | sed 's/^ */   /'
ls -la "$IPA" | awk '{print "   " $5 " bytes  " $9}'

if [[ "${DRY:-0}" == "1" ]]; then echo "== dry run, not uploading"; exit 0; fi

echo "== upload"
xcrun altool --upload-app --type ios --file "$IPA" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | grep -vE "^\s*$" | tail -3
git tag -f "ios-$VERSION-$BUILD" >/dev/null && git push -q --force origin "ios-$VERSION-$BUILD"
echo "== done: build $BUILD is processing in App Store Connect (10 to 30 min), then appears in TestFlight"
