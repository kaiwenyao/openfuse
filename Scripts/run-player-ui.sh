#!/bin/bash
# Player chrome acceptance: the subtitle / audio / speed menus must be visible
# on the black player surface in BOTH app themes, and the window appearance must
# return to the user's theme after leaving the player.
#
#   Scripts/run-player-ui.sh
#
# Regression: OpenFuse 0.4.0 defaulted to the light theme, so every AppKit-drawn
# element of the control bar (borderless Menu labels, SF Symbol buttons, the
# Slider track) was drawn black on black. The light capture used to measure
# YAVG=16 (pure black) in the menu strip; after the fix it measures ~46.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/player-ui"

if [[ ! -f "$FIXTURE" ]]; then
  Scripts/make_fixtures.sh
fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null

rm -rf "$OUT"
mkdir -p "$OUT"

capture_player() {
  local name="$1"; shift
  local support="$OUT/support-$name"
  mkdir -p "$support"
  OPENFUSE_SUPPORT_DIR="$support" OPENFUSE_FORCE_CONTROLS=1 \
    "$APP" --open "$FIXTURE" --capture-ui "$OUT/$name.png" --ui-after 6 --quit-after 8 \
    "$@" >"$OUT/$name.log" 2>&1 || true
}

capture_player light --appearance light
capture_player dark --appearance dark

# Leave the player (--reopen-test closes after 4 s) and screenshot the home
# view at 5.3 s: the scene-level colour scheme is reapplied on the next view
# update, so an exactly-at-5.0 s capture can still show the dark player theme.
mkdir -p "$OUT/support-restore"
OPENFUSE_SUPPORT_DIR="$OUT/support-restore" \
  "$APP" --appearance light --open "$FIXTURE" --reopen-test \
  --capture-ui "$OUT/restore.png" --ui-after 5.3 --quit-after 9 \
  >"$OUT/restore.log" 2>&1 || true

luma() {
  local file="$1" crop="$2"
  ffmpeg -hide_banner -loglevel info -i "$file" \
    -vf "crop=$crop,signalstats,metadata=print:key=lavfi.signalstats.YAVG" \
    -f null - 2>&1 | sed -n 's/.*YAVG=\([0-9.]*\).*/\1/p' | head -1
}

MENU_STRIP="600:200:300:1150"
LIGHT=$(luma "$OUT/light.png" "$MENU_STRIP")
DARK=$(luma "$OUT/dark.png" "$MENU_STRIP")
RESTORE=$(luma "$OUT/restore.png" "200:200:60:200")

echo "menu strip YAVG: light=$LIGHT dark=$DARK (expected >= 30 in both)"
echo "home background YAVG after leaving player: $RESTORE (expected >= 120)"

FAIL=0
python3 - "$LIGHT" "$DARK" "$RESTORE" <<'PY' || FAIL=1
import sys
light, dark, restore = (float(value) for value in sys.argv[1:4])
errors = []
if light < 30:
    errors.append(f"light theme menu strip is nearly black (YAVG={light:.1f}); menu labels are invisible again")
if dark < 30:
    errors.append(f"dark theme menu strip is nearly black (YAVG={dark:.1f})")
if restore < 120:
    errors.append(f"window did not return to the light theme after leaving the player (YAVG={restore:.1f})")
if errors:
    print("FAIL: " + "; ".join(errors))
    sys.exit(1)
print("PASS: control bar visible in light and dark themes; appearance restored on exit")
PY

if [[ "$FAIL" != "0" ]]; then
  exit 1
fi
echo "captures: $OUT"
