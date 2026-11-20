#!/bin/bash
# Jellyfin server-side HLS transcode path for MKV (fixture generates HLS from the MKV).
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=8117
HLS="$PWD/build/hls-fixture"
LOG="$PWD/build/jellyfin-hls.log"
PROBE=".build/debug/openfuse-probe"
if [[ ! -f "$HLS/index.m3u8" ]]; then
  mkdir -p "$HLS"
  ffmpeg -hide_banner -loglevel error -y -i Fixtures/generated/openfuse-fixture.mkv \
    -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2" \
    -c:v libx264 -profile:v main -pix_fmt yuv420p -c:a aac -ac 2 -b:a 160k \
    -f hls -hls_time 2 -hls_playlist_type vod \
    -hls_segment_filename "$HLS/seg%03d.ts" "$HLS/index.m3u8"
fi
: > "$LOG"
swift build --product openfuse-probe >/dev/null
python3 Tools/jellyfin_fixture.py --port "$PORT" --log "$LOG" >build/jellyfin-hls-server.log 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$PORT/System/Info/Public" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
"$PROBE" jellyfin-hls "http://127.0.0.1:$PORT" test test movie-1 > build/jellyfin-hls.json
python3 - <<'PY'
import json
data = json.load(open("build/jellyfin-hls.json"))
assert abs(data.get("duration", 0) - 60) < 1, data
assert data.get("position", 0) > 0.3, data
assert not data.get("error"), data
assert "master.m3u8" in data.get("url", ""), data
print("PASS: Jellyfin HLS transcode URL/AVPlayer playback for MKV source")
PY
