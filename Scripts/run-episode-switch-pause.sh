#!/bin/bash
# 0.9.3 regression: switching episodes from inside the player must not break
# right-click / space pausing (or any other keyboard shortcut).
#
# `startPlayer()` replaces AppModel.player with a fresh PlayerModel while the
# route stays `.player`, so PlayerView keeps its SwiftUI identity and its
# installed NSEvent monitors. Those monitors used to capture the first model
# in their closures and kept addressing the stopped engine. This script
# switches through the real folder-list path and the direct "open another file"
# path, then sends real CGEvent/AppleScript input and checks the report.
#
#   Scripts/run-episode-switch-pause.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
SECOND="$PWD/Fixtures/generated/video.mkv"
OUT="$PWD/build/episode-switch-pause"
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
  osascript -e 'tell application "System Events" to tell process "OpenFuse" to set frontmost to true' >/dev/null 2>&1 || true
}
# Real right-click at 45 % of the player window, well below the top panel.
right_click_video() {
  local raw x y w h
  raw=$(osascript -e 'tell application "System Events" to tell process "OpenFuse" to get {position of window 1, size of window 1}' 2>/dev/null || true)
  read -r x y w h <<<"$(printf '%s\n' "$raw" | python3 -c "
import sys
parts = [p.strip() for p in sys.stdin.read().strip().split(',')]
def num(value, fallback):
    try: return int(value)
    except ValueError: return fallback
if len(parts) >= 4 and parts[0] != 'missing value':
    print(*(num(p, 0) for p in parts[:4]))
else:
    print(0, 0, num(parts[-2], 1512), num(parts[-1], 949))
")"
  "$OUT/rightclick" right $((x + w / 2)) $((y + h * 45 / 100))
}

# run_case <name> <space|right|down> <none|folder|direct>
run_case() {
  local name="$1" event="$2" switch_mode="$3"
  local dir="$OUT/$name"
  rm -rf "$dir"; mkdir -p "$dir"
  local args=(--open "$FIXTURE" --report "$dir/report.json" --capture-after 8 --quit-after 10)
  case "$switch_mode" in
    folder) args+=(--folder-list --folder-select video.mkv) ;;
    direct) args+=(--switch-to "$SECOND" --switch-after 2.5) ;;
  esac
  defaults write com.openfuse.app openfuse.player.volume -float 100
  pkill -f "OpenFuse.app/Contents/MacOS/OpenFuse" 2>/dev/null || true
  OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
    "$APP" "${args[@]}" >"$dir/app.log" 2>&1 &
  local pid=$!
  sleep 5.5
  activate_app
  sleep 0.3
  case "$event" in
    space) osascript -e 'tell application "System Events" to key code 49' >/dev/null 2>&1 ;;
    right) right_click_video ;;
    down)  osascript -e 'tell application "System Events" to key code 125' >/dev/null 2>&1 ;;
  esac
  wait "$pid" || true

  local expected_file="openfuse-fixture.mkv"
  [[ "$switch_mode" != "none" ]] && expected_file="video.mkv"
  check "$(report_field "$dir/report.json" file | sed 's|.*/||')" "$expected_file" "$name: episode on screen"
  case "$event" in
    space|right)
      check "$(report_field "$dir/report.json" paused)" "True" "$name: $event pauses after switch"
      check "$(report_field "$dir/report.json" userPaused)" "True" "$name: $event recorded as user intent"
      ;;
    down)
      check "$(report_field "$dir/report.json" volume)" "95" "$name: ↓ reaches the new engine"
      check "$(report_field "$dir/report.json" currentVolumeProperty)" "95.000000" "$name: mpv volume of new engine follows"
      ;;
  esac
}

# Baseline: no switch, the shortcuts still work.
run_case no-switch-space space none
run_case no-switch-right right none

# The bug: switch episodes, then try to pause the *new* video.
run_case folder-switch-space space folder
run_case folder-switch-right right folder
run_case direct-switch-space space direct

# The same stale capture affected every shortcut; prove volume keys too.
run_case folder-switch-volume down folder

if [[ "$FAIL" != "0" ]]; then
  echo "FAIL: episode switch interactions"
  exit 1
fi
echo "PASS: right-click / space / volume keys follow episode switches"
echo "reports: $OUT"
