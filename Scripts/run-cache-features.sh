#!/bin/bash
# Cache features acceptance:
#   1. buffering HUD (percentage, cached bytes, download speed) while a slow
#      network stream stalls,
#   2. cached spans highlighted on the progress bar.
#
#   Scripts/run-cache-features.sh
#
# A fast-start H.264 copy of the fixture is served by the local WebDAV fixture
# at 30 KB/s, well below its ~90 KB/s bitrate, so playback starts and then
# stalls in `paused-for-cache`. The window capture (`--capture-window`) contains
# both the SwiftUI chrome (HUD + progress bar) and the OpenGL video surface.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/cache-features"
ROOT="$OUT/root"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"

if [[ ! -f "$FIXTURE" ]]; then
  Scripts/make_fixtures.sh
fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null

rm -rf "$OUT"
mkdir -p "$ROOT/Shows" "$OUT/support-local" "$OUT/support-net"

ffmpeg -v error -y -i "$FIXTURE" -map 0:v:0 -map 0:a:0 \
  -c:v libx264 -preset ultrafast -b:v 700k -c:a aac -b:a 128k \
  -movflags +faststart "$ROOT/Shows/fast.mp4"

# 1) Local file: the cached span must cover everything already downloaded
#    (cache-end is ahead of the playhead).
OPENFUSE_SUPPORT_DIR="$OUT/support-local" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" \
  --report "$OUT/report-local.json" \
  --capture-window "$OUT/local-window.png" --ui-after 6 \
  --capture "$OUT/local-frame.png" --capture-after 6 \
  --quit-after 8 >"$OUT/local.log" 2>&1 || true

# 2) Throttled WebDAV stream: catch `paused-for-cache` and the HUD.
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" --rate-bytes 30000 \
  >"$OUT/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -X PROPFIND -H 'Depth: 0' "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

OPENFUSE_SUPPORT_DIR="$OUT/support-net" \
OPENFUSE_WEBDAV_PASSWORD=test \
OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Throttle \
  --webdav-user admin --webdav-pass test \
  --webdav-path "Shows/fast.mp4" \
  --capture-window "$OUT/buffering-window.png" --ui-after 22 \
  --capture "$OUT/buffering-frame.png" --capture-after 22 \
  --report "$OUT/report-net.json" --quit-after 25 >"$OUT/net.log" 2>&1 || true

python3 - "$OUT" <<'PY'
import json
import os
import sys

out = sys.argv[1]
errors = []

local_path = os.path.join(out, "report-local.json")
if not os.path.exists(local_path):
    errors.append("local report missing")
else:
    local = json.load(open(local_path))
    ranges = local.get("bufferedRanges") or []
    print("local:", {key: local.get(key) for key in (
        "position", "bufferedEnd", "cacheUsedBytes", "cacheSpeedBytes", "bufferedRanges")})
    if not ranges:
        errors.append("local playback reported no cached span")
    elif ranges[0]["end"] <= local.get("position", 0):
        errors.append("local cached span does not extend past the playhead")
    if (local.get("cacheUsedBytes") or 0) <= 0:
        errors.append("local cacheUsedBytes is 0")

net_path = os.path.join(out, "report-net.json")
if not os.path.exists(net_path):
    errors.append("network report missing")
else:
    net = json.load(open(net_path))
    print("network:", {key: net.get(key) for key in (
        "position", "isBuffering", "isOpening", "bufferingPercent",
        "cacheSpeedBytes", "cacheUsedBytes", "bufferedRanges")})
    if not net.get("isBuffering"):
        errors.append("throttled stream never entered paused-for-cache")
    if (net.get("bufferingPercent") or 0) <= 0:
        errors.append("buffering percent was not reported")
    if (net.get("cacheSpeedBytes") or 0) <= 0:
        errors.append("download speed was not reported")
    if (net.get("cacheUsedBytes") or 0) <= 0:
        errors.append("cached byte count was not reported")
    if not (net.get("bufferedRanges") or []):
        errors.append("no cached span for the highlight")

for artifact in ("buffering-window.png", "buffering-frame.png", "local-window.png"):
    path = os.path.join(out, artifact)
    if not os.path.exists(path) or os.path.getsize(path) < 20_000:
        errors.append(f"missing evidence capture {artifact}")

if errors:
    print("FAIL: " + "; ".join(errors))
    sys.exit(1)
print("PASS: buffering HUD metrics and cached-span highlight verified")
PY

echo "captures: $OUT"
