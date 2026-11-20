#!/bin/bash
# Authenticated AVAssetResourceLoader test against a Basic-auth WebDAV MP4.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=8115
ROOT="$PWD/build/auth-asset-root"
LOG="$PWD/build/auth-asset.log"
PROBE=".build/debug/openfuse-probe"
rm -rf "$ROOT"; mkdir -p "$ROOT/Mobile"
cp Fixtures/mobile/openfuse-mobile.mp4 "$ROOT/Mobile/"
: > "$LOG"
swift build --product openfuse-probe >/dev/null
python3 Tools/webdav_fixture.py --root "$ROOT" --port "$PORT" --log "$LOG" >build/auth-asset-server.log 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test -I "http://127.0.0.1:$PORT/dav/Mobile/openfuse-mobile.mp4" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
"$PROBE" authed-asset "http://127.0.0.1:$PORT/dav/Mobile/openfuse-mobile.mp4" test test > build/auth-asset.json
python3 - <<'PY'
import json
data = json.load(open("build/auth-asset.json"))
assert abs(data.get("duration", 0) - 20) < 0.2, data
assert data.get("videoTracks") == 1, data
assert data.get("width") == 1280 and data.get("height") == 720, data
print("PASS: authenticated AVAsset load, duration/track/size via WebDAV Basic auth")
PY
"$PROBE" authed-play "http://127.0.0.1:$PORT/dav/Mobile/openfuse-mobile.mp4" test test > build/auth-play.json
python3 - <<'PY'
import json
data = json.load(open("build/auth-play.json"))
assert data.get("position", 0) > 0.3, data
assert not data.get("error"), data
print("PASS: AVPlayer advanced with authenticated WebDAV stream")
PY
"$PROBE" authed-asset "http://127.0.0.1:$PORT/dav/Mobile/openfuse-mobile.mp4" test wrong > build/auth-asset-bad.json
python3 - <<'PY'
import json
data = json.load(open("build/auth-asset-bad.json"))
assert "error" in data, data
print("PASS: wrong credentials fail asset load")
PY
