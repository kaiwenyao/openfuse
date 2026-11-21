#!/bin/bash
# Scrubber hover thumbnail acceptance for 0.5.5:
#   - hovering the progress bar previews a 320×180 frame near the cursor,
#   - playback keeps running (the preview engine never seeks the player),
#   - local files and WebDAV sources both work,
#   - no request is made when the cursor is not over the bar,
#   - the preview also works in fullscreen.
#
#   Scripts/run-thumbnail-preview.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/thumbnail-preview"
mkdir -p "$OUT"

Scripts/build-app.sh >/dev/null
swift test >/dev/null
swiftc -O Tools/click_event.swift -o "$OUT/event"

FAIL=0
check() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL $3: expected $2, got $1"
    FAIL=1
  else
    echo "ok   $3: $1"
  fi
}
report() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "$@"; }

activate_app() {
  osascript -e 'tell application "OpenFuse" to activate' >/dev/null 2>&1
  sleep 0.4
}

geometry() {
  osascript -e 'tell application "System Events" to tell process "OpenFuse" to get {position of window 1, size of window 1}' \
    | python3 -c "
import sys
parts = [p.strip() for p in sys.stdin.read().strip().split(',') if p.strip()]
def num(v, d):
    try: return int(v)
    except ValueError: return d
if len(parts) >= 4 and parts[0] != 'missing value':
    x, y, w, h = (num(p, 0) for p in parts[:4])
elif len(parts) >= 2:
    x, y = 0, 0
    w, h = num(parts[-2], 1512), num(parts[-1], 949)
else:
    x, y, w, h = 0, 0, 1512, 949
print(x, y, w, h)
"
}

# Hover with a staged entry so SwiftUI's tracking area sees the enter + move.
hover_bar() {
  local percent="$1"
  local x y w h
  for _ in {1..10}; do
    read -r x y w h <<<"$(geometry)"
    [[ "$w" -gt 200 && "$h" -gt 200 ]] && break
    sleep 0.3
  done
  local barY=$((y + h - 98))
  "$OUT/event" move $((x + w / 2)) $((y + h / 2))
  sleep 0.25
  "$OUT/event" move $((x + w * percent / 100)) "$barY"
  sleep 0.25
  "$OUT/event" move $((x + w * percent / 100 + 5)) "$barY"
}

# --- local file: two hover positions, second preview captured -------------
dir="$OUT/local"
rm -rf "$dir"; mkdir -p "$dir" "$OUT/thumbs-local"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_THUMBNAIL_DIR="$OUT/thumbs-local" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --capture-window "$dir/window.png" --ui-after 8 \
  --report "$dir/report.json" --capture-after 8 --quit-after 10 >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
hover_bar 25
sleep 2.0
hover_bar 70
wait "$pid" || true
local_cache=$(report "$dir/report.json" thumbnailCacheCount)
local_bytes=$(report "$dir/report.json" thumbnailLastBytes)
local_pos=$(report "$dir/report.json" position)
check "$local_cache" "2" "two hover buckets cached"
[[ "$local_bytes" -gt 5000 ]]; check "$?" "0" "thumbnail PNG has data"
python3 - "$dir/report.json" <<'PY' && echo "ok   playback not seeked by preview" || { echo "FAIL playback seeked by preview"; FAIL=1; }
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if (d.get("position") or 0) > 4 and not d.get("paused") else 1)
PY
[[ -s "$dir/window.png" ]]; check "$?" "0" "hover preview window capture"
[[ -s "$OUT/thumbs-local/00000001.png" ]]; check "$?" "0" "preview PNG written"
dims=$(sips -g pixelWidth -g pixelHeight "$OUT/thumbs-local/00000001.png" 2>/dev/null | awk '/pixelWidth|pixelHeight/{print $2}' | paste -sd 'x' -)
check "$dims" "320x180" "thumbnail resolution"

# --- no hover over the bar: no preview work ------------------------------
dir="$OUT/no-hover"
rm -rf "$dir"; mkdir -p "$dir" "$OUT/thumbs-none"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_THUMBNAIL_DIR="$OUT/thumbs-none" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --capture-window "$dir/window.png" --ui-after 6 \
  --report "$dir/report.json" --capture-after 6 --quit-after 8 >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
read -r x y w h <<<"$(geometry)"
"$OUT/event" move $((x + w / 2)) $((y + h / 2))
sleep 0.4
"$OUT/event" move $((x + w / 3)) $((y + h / 3))
wait "$pid" || true
check "$(report "$dir/report.json" thumbnailCacheCount)" "0" "no thumbnail work off the bar"

# --- WebDAV source --------------------------------------------------------
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 Scripts/webdav_fixture.py --root "$PWD/build/cache-features/root" --port "$PORT" \
  >"$OUT/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 1
dir="$OUT/webdav"
rm -rf "$dir"; mkdir -p "$dir" "$OUT/thumbs-webdav"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_THUMBNAIL_DIR="$OUT/thumbs-webdav" \
OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name T --webdav-user admin --webdav-pass test \
  --webdav-path "Shows/fast.mp4" --capture-window "$dir/window.png" --ui-after 10 \
  --report "$dir/report.json" --capture-after 10 --quit-after 13 >"$dir/app.log" 2>&1 &
pid=$!
sleep 3.5; activate_app
hover_bar 50
wait "$pid" || true
check "$(report "$dir/report.json" thumbnailCacheCount)" "1" "WebDAV hover thumbnail cached"
webdav_pos=$(report "$dir/report.json" position)
python3 - "$dir/report.json" <<'PY' && echo "ok   WebDAV playback not seeked" || { echo "FAIL WebDAV playback seeked"; FAIL=1; }
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if (d.get("position") or 0) > 7 else 1)
PY
[[ -s "$OUT/thumbs-webdav/00000001.png" ]]; check "$?" "0" "WebDAV preview PNG written"
[[ -s "$dir/window.png" ]]; check "$?" "0" "WebDAV preview window capture"
kill "$SERVER_PID" >/dev/null 2>&1 || true

# --- cross-restart disk cache --------------------------------------------
dir="$OUT/cache-restart"
rm -rf "$dir"; mkdir -p "$dir"
for pass in 1 2; do
  OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
    "$APP" --open "$FIXTURE" --report "$dir/report-$pass.json" --capture-after 7 --quit-after 9 \
    >"$dir/app-$pass.log" 2>&1 &
  pid=$!
  sleep 2.4; activate_app
  hover_bar 34
  wait "$pid" || true
done
first_source=$(report "$dir/report-1.json" thumbnailLastSource)
second_source=$(report "$dir/report-2.json" thumbnailLastSource)
second_hits=$(report "$dir/report-2.json" thumbnailDiskHits)
[[ "$second_hits" -ge 1 ]]; check "$?" "0" "restart reuses disk thumbnail ($second_hits hits, source=$second_source)"

# --- cold/hot benchmark (15 cold + 15 hot samples) -----------------------
dir="$OUT/benchmark"
rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_THUMB_BENCHMARK=1 OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --report "$dir/report.json" --capture-after 15 --quit-after 18 \
  >"$dir/app.log" 2>&1
cold_p50=$(report "$dir/report.json" thumbnailBenchmarkP50)
cold_p95=$(report "$dir/report.json" thumbnailBenchmarkP95)
hot_p95=$(report "$dir/report.json" thumbnailBenchmarkHotP95)
samples=$(report "$dir/report.json" thumbnailBenchmarkSamples)
check "$samples" "30" "benchmark samples"
echo "thumbnail benchmark: cold P50=${cold_p50}ms P95=${cold_p95}ms hot P95=${hot_p95}ms"

# --- fullscreen -----------------------------------------------------------
dir="$OUT/fullscreen"
rm -rf "$dir"; mkdir -p "$dir" "$OUT/thumbs-fullscreen"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_THUMBNAIL_DIR="$OUT/thumbs-fullscreen" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --fullscreen --capture-window "$dir/window.png" --ui-after 9 \
  --report "$dir/report.json" --capture-after 9 --quit-after 11 >"$dir/app.log" 2>&1 &
pid=$!
sleep 5.2; activate_app
hover_bar 60
wait "$pid" || true
fs_cache=$(report "$dir/report.json" thumbnailCacheCount)
[[ "$fs_cache" -ge 1 ]]; check "$?" "0" "fullscreen hover thumbnail cached"

if [[ "$FAIL" != "0" ]]; then
  echo "FAIL: thumbnail preview"
  exit 1
fi
echo "PASS: scrubber hover thumbnails (local, no-hover, WebDAV, fullscreen)"
echo "captures: $OUT"
