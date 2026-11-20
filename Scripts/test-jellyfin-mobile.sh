#!/bin/bash
# Jellyfin mobile remote path: auth -> PlaybackInfo -> token URL -> loader -> AVPlayer.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=8116
ROOT="$PWD/build/jellyfin-mobile"
LOG="$PWD/build/jellyfin-mobile.log"
PROBE=".build/debug/openfuse-probe"
rm -rf "$ROOT"; mkdir -p "$ROOT"; : > "$LOG"
swift build --product openfuse-probe >/dev/null
python3 Tools/jellyfin_fixture.py --port "$PORT" --mobile-sample --log "$LOG" >build/jellyfin-mobile-server.log 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$PORT/System/Info/Public" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
"$PROBE" jellyfin-remote "http://127.0.0.1:$PORT" test test movie-mobile > build/jellyfin-mobile.json
python3 - <<'PY'
import json
data = json.load(open("build/jellyfin-mobile.json"))
assert abs(data.get("duration", 0) - 20) < 0.2, data
assert data.get("videoTracks") == 1, data
assert data.get("position", 0) > 0.3, data
assert not data.get("error"), data
assert "api_key=" in data.get("url", ""), data
print("PASS: Jellyfin auth/PlaybackInfo/token URL/loader/AVPlayer remote playback")
PY
