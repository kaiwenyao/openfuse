#!/bin/bash
# IINA-style window management acceptance for 0.6.0:
#   ⌘0 half size, ⌘1 native size, ⌘2 double size, ⌘4 fit-to-screen,
#   ⌘- smaller, ⌘= bigger, ⌘3 fullscreen, Esc exit fullscreen,
#   ⌃⌘F fullscreen (standard shortcut), ⌃⌘T always-on-top on/off.
#
#   Scripts/run-window-management.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/window-management"
SMALL="$OUT/small-640x360.mp4"
mkdir -p "$OUT"

Scripts/build-app.sh >/dev/null
swift test >/dev/null
ffmpeg -v error -y -i "$FIXTURE" -t 20 -vf scale=640:360 \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 96k "$SMALL"

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
activate_app() { osascript -e 'tell application "OpenFuse" to activate' >/dev/null 2>&1; sleep 0.4; }
ax_size() {
  osascript -e 'tell application "System Events" to tell process "OpenFuse" to get size of window 1' 2>/dev/null \
    | tr -d ' ' || echo "0,0"
}
wait_report() {
  local path="$1"
  for _ in {1..40}; do
    [[ -s "$path" ]] && return 0
    sleep 0.5
  done
  return 1
}
press() { # keystroke modifiers label
  osascript -e "tell application \"System Events\" to keystroke \"$1\" using $2" >/dev/null 2>&1
  sleep 0.8
}
press_key() { # keycode modifiers label
  if [[ -n "$2" ]]; then
    osascript -e "tell application \"System Events\" to key code $1 using $2" >/dev/null 2>&1
  else
    osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1
  fi
  sleep 0.8
}

# --- sizes ---------------------------------------------------------------
dir="$OUT/sizes"
rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$SMALL" --report "$dir/report.json" --capture-after 12 --quit-after 14 \
  >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
initial=$(ax_size)
echo "ok   initial window: $initial"

press 0 "command down"; half=$(ax_size)
check "$(echo "$half" | cut -d, -f1)" "320" "⌘0 half width"
half_h=$(echo "$half" | cut -d, -f2 | tr -d ' ')
[[ "$half_h" -ge 180 && "$half_h" -le 230 ]]; check "$?" "0" "⌘0 half height ~180"

press 1 "command down"; normal=$(ax_size)
check "$(echo "$normal" | cut -d, -f1)" "640" "⌘1 native width"
normal_h=$(echo "$normal" | cut -d, -f2 | tr -d ' ')
[[ "$normal_h" -ge 350 && "$normal_h" -le 380 ]]; check "$?" "0" "⌘1 native height ~360"

press 2 "command down"; double=$(ax_size)
check "$(echo "$double" | cut -d, -f1)" "1280" "⌘2 double width"
double_h=$(echo "$double" | cut -d, -f2 | tr -d ' ')
[[ "$double_h" -ge 700 && "$double_h" -le 750 ]]; check "$?" "0" "⌘2 double height ~720"

press 4 "command down"; fit=$(ax_size)
fit_w=$(echo "$fit" | cut -d, -f1); fit_h=$(echo "$fit" | cut -d, -f2 | tr -d ' ')
[[ "$fit_w" -ge 1350 && "$fit_w" -le 1460 ]]; check "$?" "0" "⌘4 fit width"
[[ "$fit_h" -ge 750 && "$fit_h" -le 830 ]]; check "$?" "0" "⌘4 fit height"
python3 - "$fit_w" "$fit_h" <<'PY' && echo "ok   fit keeps 16:9" || { echo "FAIL fit aspect"; exit 1; }
import sys
w, h = float(sys.argv[1]), float(sys.argv[2])
sys.exit(0 if abs(w / h - 16 / 9) < 0.05 else 1)
PY

press_key 27 "command down"  # ⌘-
smaller=$(ax_size)
smaller_w=$(echo "$smaller" | cut -d, -f1)
[[ "$smaller_w" -lt "$fit_w" && "$smaller_w" -gt $((fit_w * 85 / 100)) ]]; check "$?" "0" "⌘- smaller"

press_key 24 "command down"  # ⌘= (keycode 24 is '=' on US layout)
bigger=$(ax_size)
bigger_w=$(echo "$bigger" | cut -d, -f1)
[[ "$bigger_w" -gt "$smaller_w" ]]; check "$?" "0" "⌘= bigger"

wait_report "$dir/report.json" || { echo "FAIL sizes report missing"; FAIL=1; }
check "$(report "$dir/report.json" windowScaleLastAction)" "bigger" "last scale action recorded"
wait "$pid" || true

# --- ⌘3 fullscreen -------------------------------------------------------
dir="$OUT/fullscreen"
rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$SMALL" --capture-window "$dir/window.png" \
  --report "$dir/report.json" --capture-after 6 --quit-after 8 >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
press 3 "command down"
wait_report "$dir/report.json" || { echo "FAIL fullscreen report missing"; FAIL=1; }
check "$(report "$dir/report.json" isFullScreen)" "True" "⌘3 enters fullscreen"
[[ -s "$dir/window.png" ]]; check "$?" "0" "fullscreen capture"
wait "$pid" || true

# --- Esc leaves fullscreen ----------------------------------------------
dir="$OUT/esc"
rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$SMALL" --report "$dir/report.json" --capture-after 7 --quit-after 9 >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
press 3 "command down"
sleep 1.0
press_key 53 ""
wait_report "$dir/report.json" || { echo "FAIL esc report missing"; FAIL=1; }
check "$(report "$dir/report.json" isFullScreen)" "False" "Esc leaves fullscreen"
wait "$pid" || true

# --- ⌃⌘F fullscreen (standard shortcut) ---------------------------------
dir="$OUT/ctrlcmdf"
rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$SMALL" --report "$dir/report.json" --capture-after 6 --quit-after 8 >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
osascript -e 'tell application "System Events" to keystroke "f" using {control down, command down}' >/dev/null 2>&1
sleep 1.0
wait_report "$dir/report.json" || { echo "FAIL ctrl-cmd-f report missing"; FAIL=1; }
check "$(report "$dir/report.json" isFullScreen)" "True" "⌃⌘F enters fullscreen"
wait "$pid" || true

# --- always on top -------------------------------------------------------
dir="$OUT/ontop-on"
rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$SMALL" --report "$dir/report.json" --capture-after 6 --quit-after 8 >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
osascript -e 'tell application "System Events" to keystroke "t" using {control down, command down}' >/dev/null 2>&1
sleep 0.8
wait_report "$dir/report.json" || { echo "FAIL ontop report missing"; FAIL=1; }
check "$(report "$dir/report.json" alwaysOnTop)" "True" "⌃⌘T turns always-on-top on"
check "$(report "$dir/report.json" windowLevel)" "3" "window level floating"
wait "$pid" || true

dir="$OUT/ontop-off"
rm -rf "$dir"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$SMALL" --report "$dir/report.json" --capture-after 7 --quit-after 9 >"$dir/app.log" 2>&1 &
pid=$!
sleep 2.4; activate_app
osascript -e 'tell application "System Events" to keystroke "t" using {control down, command down}' >/dev/null 2>&1
sleep 0.8
osascript -e 'tell application "System Events" to keystroke "t" using {control down, command down}' >/dev/null 2>&1
sleep 0.8
wait_report "$dir/report.json" || { echo "FAIL ontop off report missing"; FAIL=1; }
check "$(report "$dir/report.json" alwaysOnTop)" "False" "⌃⌘T turns always-on-top off"
check "$(report "$dir/report.json" windowLevel)" "0" "window level normal"
wait "$pid" || true

if [[ "$FAIL" != "0" ]]; then
  echo "FAIL: window management"
  exit 1
fi
echo "PASS: IINA-style window sizes, ⌘3/⌃⌘F fullscreen, Esc, always-on-top"
echo "captures: $OUT"
