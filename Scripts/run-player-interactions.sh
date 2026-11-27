#!/bin/bash
# Player interaction acceptance for 0.5.4:
#   - ↑/↓ volume (5 % steps, mpv volume follows, persisted),
#   - right-click toggles play/pause on the video, the letterbox, the control
#     bar and in fullscreen,
#   - pausing during buffering survives the cache recovery.
#
#   Scripts/run-player-interactions.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/player-interactions"
mkdir -p "$OUT"

Scripts/build-app.sh >/dev/null
swift test >/dev/null
swiftc -O Tools/click_event.swift -o "$OUT/rightclick"

FAIL=0
check() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL $3: expected $2, got $1"
    FAIL=1
  else
    echo "ok   $3: $1"
  fi
}
report_field() {
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2]))" "$@"
}
activate_app() {
  osascript -e 'tell application "System Events" to tell process "OpenFuse" to set frontmost to true' >/dev/null 2>&1
}
geometry() {
  local raw
  raw=$(osascript -e 'tell application "System Events" to tell process "OpenFuse" to get {position of window 1, size of window 1}' 2>/dev/null || true)
  if [[ -z "$raw" ]]; then
    # During native fullscreen System Events sometimes has no window to
    # enumerate for a frame; the fullscreen window covers the screen.
    echo "0 0 1512 982"
    return
  fi
  printf '%s\n' "$raw" | python3 -c "
import sys
parts = [p.strip() for p in sys.stdin.read().strip().split(',')]
def num(value, fallback):
    try: return int(value)
    except ValueError: return fallback
if len(parts) >= 4 and parts[0] != 'missing value':
    x, y, w, h = (num(p, 0) for p in parts[:4])
else:
    # Fullscreen AX position is 'missing value'; the window covers the screen.
    x, y = 0, 0
    w, h = num(parts[-2], 1512), num(parts[-1], 949)
print(x, y, w, h)
"
}
click_region() {
  local region="$1"; local x y w h
  read -r x y w h <<<"$(geometry)"
  case "$region" in
    video) "$OUT/rightclick" right $((x + w / 2)) $((y + h * 45 / 100)) ;;
    letterbox) "$OUT/rightclick" right $((x + w / 2)) $((y + 90)) ;;
    controlbar) "$OUT/rightclick" right $((x + w / 2)) $((y + h - 60)) ;;
    fullscreen) "$OUT/rightclick" right $((x + w / 2)) $((y + h / 2)) ;;
  esac
}

# --- volume: reset to 100, then ↓ ↓ ↑ = 95 --------------------------------
defaults write com.openfuse.app openfuse.player.volume -float 100
dir="$OUT/volume"; rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --report "$dir/report.json" --capture-after 6 --quit-after 8 \
  >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.0; activate_app; sleep 0.3
osascript -e 'tell application "System Events" to key code 125' \
          -e 'delay 0.1' \
          -e 'tell application "System Events" to key code 125' \
          -e 'delay 0.1' \
          -e 'tell application "System Events" to key code 126' >/dev/null 2>&1
wait "$pid" || true
check "$(report_field "$dir/report.json" volume)" "95" "arrow keys change in-app volume"
check "$(report_field "$dir/report.json" currentVolumeProperty)" "95.000000" "mpv volume follows"

# --- right-click: one click pauses in each region -------------------------
for region in video letterbox controlbar; do
  dir="$OUT/right-$region"; rm -rf "$dir"; mkdir -p "$dir"
  OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
    "$APP" --open "$FIXTURE" --report "$dir/report.json" --capture-after 6 --quit-after 8 \
    >"$dir/app.log" 2>&1 &
  pid=$!
  sleep 2.0; activate_app; sleep 0.3; click_region "$region"
  wait "$pid" || true
  check "$(report_field "$dir/report.json" paused)" "True" "right click toggles in $region"
  check "$(report_field "$dir/report.json" userPaused)" "True" "pause in $region recorded as user intent"
done

# --- right-click: two clicks resume ---------------------------------------
dir="$OUT/right-resume"; rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --report "$dir/report.json" --capture-after 6 --quit-after 8 \
  >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.0; activate_app; sleep 0.3; click_region video; sleep 1; click_region video
wait "$pid" || true
check "$(report_field "$dir/report.json" paused)" "False" "two right clicks resume"

# --- fullscreen -----------------------------------------------------------
dir="$OUT/right-fullscreen"; rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --fullscreen --report "$dir/report.json" --capture-after 8 --quit-after 10 \
  >"$dir/app.log" 2>&1 &
pid=$!
# The fullscreen transition moves the window to its own Space. On a large display
# (2560x1440 here) the animation takes longer than 4 s, and a click posted before
# it finishes lands on the desktop Space and is lost — the same failure happens on
# the pre-fix build, so this is a timing guard, not a behaviour change.
sleep 6.0
# Fullscreen focus occasionally needs a moment after the animation.
for _ in {1..10}; do
  [[ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null | tr -d '\n')" == "OpenFuse" ]] && break
  activate_app
  open -a "$PWD/build/OpenFuse.app" >/dev/null 2>&1
  sleep 0.3
done
sleep 0.6
# Park the cursor inside the video first: `left` posts a mouseMoved, `right` does
# not, and a right-click into a freshly entered fullscreen Space is otherwise
# dropped.
read -r gx gy gw gh <<<"$(geometry)"
"$OUT/rightclick" move $((gx + gw / 2)) $((gy + gh / 2))
sleep 0.3
click_region fullscreen
wait "$pid" || true
check "$(report_field "$dir/report.json" paused)" "True" "right click toggles in fullscreen"
check "$(report_field "$dir/report.json" isFullScreen)" "True" "fullscreen window was used"

# --- pause during buffering survives cache recovery -----------------------
dir="$OUT/buffered-pause"; rm -rf "$dir"; mkdir -p "$dir"
# These two cases stream from the cache-features tree. Scripts/run-cache-features.sh
# builds it, but this script must not depend on another run having happened:
# generate the same faststart MP4 when the tree is absent.
CACHE_ROOT="$PWD/build/cache-features/root"
if [[ ! -f "$CACHE_ROOT/Shows/fast.mp4" ]]; then
  mkdir -p "$CACHE_ROOT/Shows"
  ffmpeg -v error -y -i "$FIXTURE" -map 0:v:0 -map 0:a:0 \
    -c:v libx264 -preset ultrafast -b:v 700k -c:a aac -b:a 128k \
    -movflags +faststart "$CACHE_ROOT/Shows/fast.mp4"
fi
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 Scripts/webdav_fixture.py --root "$CACHE_ROOT" --port "$PORT" \
  --rate-bytes 60000 --stall-after-bytes 240000 --stall-seconds 8 >"$dir/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 1
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name T --webdav-user admin --webdav-pass test \
  --webdav-path "Shows/fast.mp4" --report "$dir/report.json" --capture-after 24 --quit-after 27 \
  >"$dir/app.log" 2>&1 &
pid=$!
sleep 10; activate_app; sleep 0.3; click_region video
wait "$pid" || true
check "$(report_field "$dir/report.json" paused)" "True" "pause during buffering is kept after recovery"
check "$(report_field "$dir/report.json" userPaused)" "True" "buffering pause recorded as user intent"
check "$(report_field "$dir/report.json" isBuffering)" "False" "buffering finished while staying paused"

if [[ "$FAIL" != "0" ]]; then
  echo "FAIL: player interactions"
  exit 1
fi
echo "PASS: volume keys, right-click regions/fullscreen, buffered pause"
echo "captures: $OUT"
