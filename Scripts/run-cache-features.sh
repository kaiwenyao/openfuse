#!/bin/bash
# Cache acceptance for 0.5.4:
#   1. local file: cached spans cover the downloaded part of the bar,
#   2. delayed first byte: opening HUD shows "测速中…" (no speed sample yet),
#   3. throttled stream with a mid-playback stall: buffering HUD with a speed
#      sample and a cached span,
#   4. killed stream: "连接中断" with a measured 0 B/s,
#   5. recovery: pressing play/space on the stalled HUD reloads at the last
#      position and resumes when the server is back.
#
#   Scripts/run-cache-features.sh
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
mkdir -p "$ROOT/Shows" "$OUT/support-local" "$OUT/support-open" "$OUT/support-net" "$OUT/support-dead" "$OUT/support-recover"

ffmpeg -v error -y -i "$FIXTURE" -map 0:v:0 -map 0:a:0 \
  -c:v libx264 -preset ultrafast -b:v 700k -c:a aac -b:a 128k \
  -movflags +faststart "$ROOT/Shows/fast.mp4"

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

kill_server() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}
trap kill_server EXIT

# 1) Local file: the cached span must cover everything already downloaded.
OPENFUSE_SUPPORT_DIR="$OUT/support-local" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" \
  --report "$OUT/report-local.json" \
  --capture-window "$OUT/local-window.png" --ui-after 6 \
  --capture "$OUT/local-frame.png" --capture-after 6 \
  --quit-after 8 >"$OUT/local.log" 2>&1 || true

# 2) Delayed first byte: opening, no speed sample yet.
PORT=$(free_port)
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" --first-byte-delay 5 \
  >"$OUT/server-open.log" 2>&1 &
SERVER_PID=$!
sleep 1
OPENFUSE_SUPPORT_DIR="$OUT/support-open" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Open \
  --webdav-user admin --webdav-pass test --webdav-path "Shows/fast.mp4" \
  --capture-window "$OUT/opening-hud.png" --ui-after 3 \
  --report "$OUT/report-open.json" --capture-after 3 --quit-after 8 >"$OUT/open.log" 2>&1 || true
kill_server

# 3) Throttled stream with a stall: buffering HUD with speed and cached span.
PORT=$(free_port)
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" --rate-bytes 30000 \
  --stall-after-bytes 180000 --stall-seconds 12 >"$OUT/server-buffer.log" 2>&1 &
SERVER_PID=$!
sleep 1
OPENFUSE_SUPPORT_DIR="$OUT/support-net" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Throttle \
  --webdav-user admin --webdav-pass test --webdav-path "Shows/fast.mp4" \
  --capture-window "$OUT/buffering-window.png" --ui-after 16 \
  --capture "$OUT/buffering-frame.png" --capture-after 16 \
  --report "$OUT/report-net.json" --quit-after 19 >"$OUT/net.log" 2>&1 || true
kill_server

# 4) Dead stream: measured zero speed and the stalled HUD.
PORT=$(free_port)
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" --rate-bytes 30000 \
  >"$OUT/server-dead.log" 2>&1 &
SERVER_PID=$!
sleep 1
OPENFUSE_SUPPORT_DIR="$OUT/support-dead" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Dead \
  --webdav-user admin --webdav-pass test --webdav-path "Shows/fast.mp4" \
  --capture-window "$OUT/stream-dead.png" --ui-after 16 \
  --report "$OUT/report-dead.json" --capture-after 16 --quit-after 19 >"$OUT/dead.log" 2>&1 &
APP_PID=$!
sleep 8
kill_server
wait "$APP_PID" || true

# 5) Recovery: press space on the stalled HUD after the server is back.
PORT=$(free_port)
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" --rate-bytes 30000 \
  >"$OUT/server-recover1.log" 2>&1 &
SERVER_PID=$!
sleep 1
OPENFUSE_SUPPORT_DIR="$OUT/support-recover" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Recover \
  --webdav-user admin --webdav-pass test --webdav-path "Shows/fast.mp4" \
  --capture-window "$OUT/recovered.png" --ui-after 28 \
  --report "$OUT/report-recover.json" --capture-after 28 --quit-after 31 >"$OUT/recover.log" 2>&1 &
APP_PID=$!
sleep 8
kill_server
sleep 5
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" --rate-bytes 30000 \
  >"$OUT/server-recover2.log" 2>&1 &
SERVER_PID=$!
sleep 6
osascript -e 'tell application "OpenFuse" to activate' >/dev/null 2>&1
sleep 0.4
osascript -e 'tell application "System Events" to key code 49' >/dev/null 2>&1
wait "$APP_PID" || true
kill_server

python3 - "$OUT" <<'PY'
import json
import os
import sys

out = sys.argv[1]
errors = []

def load(name):
    path = os.path.join(out, name)
    if not os.path.exists(path):
        errors.append(f"{name} missing")
        return None
    return json.load(open(path))

local = load("report-local.json")
if local:
    ranges = local.get("bufferedRanges") or []
    print("local:", {k: local.get(k) for k in ("position", "bufferedEnd", "cacheUsedBytes", "bufferedRanges")})
    if not ranges:
        errors.append("local playback reported no cached span")
    elif ranges[0]["end"] <= local.get("position", 0):
        errors.append("local cached span does not extend past the playhead")
    if (local.get("cacheUsedBytes") or 0) <= 0:
        errors.append("local cacheUsedBytes is 0")

opening = load("report-open.json")
if opening:
    print("opening:", {k: opening.get(k) for k in ("isOpening", "hasSpeedSample", "cacheSpeedBytes")})
    if not opening.get("isOpening"):
        errors.append("delayed-open report left the opening state too early")
    if opening.get("hasSpeedSample"):
        errors.append("speed sample appeared before the first byte was served")

net = load("report-net.json")
if net:
    print("buffering:", {k: net.get(k) for k in (
        "position", "isBuffering", "isNetworkStalled", "bufferingPercent",
        "cacheSpeedBytes", "cacheUsedBytes", "bufferedRanges")})
    if not (net.get("isBuffering") or net.get("isNetworkStalled")):
        errors.append("throttled stream showed no buffering feedback")
    if not net.get("hasSpeedSample"):
        errors.append("buffering state has no speed sample")
    if not (net.get("bufferedRanges") or []):
        errors.append("no cached span for the highlight")

dead = load("report-dead.json")
if dead:
    print("dead:", {k: dead.get(k) for k in ("position", "isNetworkStalled", "hasSpeedSample", "cacheSpeedBytes")})
    if not dead.get("isNetworkStalled"):
        errors.append("killed stream was not reported as stalled")
    if dead.get("cacheSpeedBytes") != 0:
        errors.append(f"dead stream speed is not 0 ({dead.get('cacheSpeedBytes')})")
    if not dead.get("hasSpeedSample"):
        errors.append("dead stream has no speed sample state")

recover = load("report-recover.json")
if recover:
    print("recover:", {k: recover.get(k) for k in ("position", "isNetworkStalled", "isBuffering", "hasSpeedSample", "cacheSpeedBytes")})
    if recover.get("isNetworkStalled"):
        errors.append("recovery did not clear the stalled state")
    if (recover.get("position") or 0) < 1:
        errors.append("recovery did not resume playback")
    if not recover.get("hasSpeedSample"):
        errors.append("recovered stream has no speed sample")

for artifact in ("opening-hud.png", "buffering-window.png", "buffering-frame.png",
                 "stream-dead.png", "recovered.png", "local-window.png"):
    path = os.path.join(out, artifact)
    if not os.path.exists(path) or os.path.getsize(path) < 20_000:
        errors.append(f"missing evidence capture {artifact}")

if errors:
    print("FAIL: " + "; ".join(errors))
    sys.exit(1)
print("PASS: opening/measuring, buffering speed, zero-speed stall, recovery and cached spans verified")
PY

echo "captures: $OUT"
