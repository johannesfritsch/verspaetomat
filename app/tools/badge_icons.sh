#!/usr/bin/env bash
# Prepares the achievement icons in assets/achievements for the app: the near-white ground
# outside the ring becomes transparent (flood fill from the corner, so the clock face stays)
# and the image is trimmed to the ring. Idempotent; run after dropping new PNGs in.
set -euo pipefail
cd "$(dirname "$0")/../assets/achievements"
for f in *.png; do
  magick "$f" -fuzz 4% -fill none -draw 'alpha 0,0 floodfill' -trim +repage "$f"
done
magick identify -format '%f %wx%h\n' *.png | sort | head -3
