#!/bin/sh
# Renders the three demo puzzle videos (docs/51 §9b) from the scenes in this folder.
# Frame 0 of each is the still in app/assets/demo/puzzles/<name>.webp: every animation in the
# scenes starts at rest. Needs Google Chrome, node ≥ 22 and ffmpeg.
#
#   app/tools/demo-puzzles/make.sh [out-dir]     # default: app/assets/demo/puzzles
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/../../assets/demo/puzzles}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for n in bahnhofsmission wald kinderhospiz; do
  node "$here/render.mjs" "$here/$n.html" "$work/$n" 20 30
done

# The station's two-tone chime at the start, so playback with sound can be tested.
ffmpeg -y -loglevel error \
  -f lavfi -i "sine=frequency=659.25:duration=0.9" -f lavfi -i "sine=frequency=523.25:duration=1.4" \
  -filter_complex "[0]afade=t=in:d=0.02,afade=t=out:st=0.5:d=0.4,volume=0.25[a];[1]afade=t=in:d=0.02,afade=t=out:st=0.6:d=0.8,volume=0.25,adelay=700|700[b];[a][b]amix=inputs=2:normalize=0,apad=whole_dur=20[out]" \
  -map "[out]" -ac 2 -ar 44100 "$work/chime.wav"

ffmpeg -y -loglevel error -framerate 30 -i "$work/bahnhofsmission/f%04d.png" -i "$work/chime.wav" \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 23 -preset slow -c:a aac -b:a 96k -shortest \
  -movflags +faststart "$out/bahnhofsmission.mp4"
for n in wald kinderhospiz; do
  ffmpeg -y -loglevel error -framerate 30 -i "$work/$n/f%04d.png" -an \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 23 -preset slow -movflags +faststart "$out/$n.mp4"
done
ls -la "$out"/*.mp4
