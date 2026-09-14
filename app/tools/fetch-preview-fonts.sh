#!/usr/bin/env bash
# Fetch the app's two faces so tools/preview_test.dart can draw real type.
#
# The bench has no network, and google_fonts downloads at runtime, so on the bench every glyph
# falls back to the platform face — which has different metrics and makes a layout check lie.
# This drops static TTFs into a gitignored folder; the bench loads them if they are there and
# carries on without them if they are not.
#
#   app/tools/fetch-preview-fonts.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=".preview-fonts"
mkdir -p "$OUT"

# An ancient User-Agent, because Google Fonts serves woff2 to anything modern and Flutter's
# FontLoader wants a TTF.
CSS="$(curl -fsS -H 'User-Agent: Mozilla/4.0' \
  'https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700;800&family=Caveat:wght@500')"

# The urls come back in the order the weights were asked for, one @font-face block each. No
# mapfile here: macOS still ships bash 3.2 and does not have it.
NAMES="Archivo_regular Archivo_500 Archivo_600 Archivo_700 Archivo_800 Caveat_500"
i=1
for name in $NAMES; do
  url="$(grep -oE 'https://[^)]*\.ttf' <<<"$CSS" | sed -n "${i}p")"
  [ -n "$url" ] || { echo "no url for $name — did the Google Fonts response change?"; exit 1; }
  curl -fsS -o "$OUT/$name.ttf" "$url"
  echo "  $name.ttf"
  i=$((i + 1))
done
echo "fonts in app/$OUT — run: flutter test tools/preview_test.dart"
