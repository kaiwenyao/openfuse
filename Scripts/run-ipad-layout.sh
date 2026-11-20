#!/bin/bash
# M6h: iPad regular-width split-view layout smoke test.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${OPENFUSE_IPAD_SIM:-477B8FDD-14A2-46A1-8821-76799414DA98}"
BUNDLE=com.openfuse.mobile
OUT="$PWD/build/ipad-layout"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-ios.sh "platform=iOS Simulator,id=$SIM" "$OUT/build" Debug >/dev/null
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$OUT/build/Build/Products/Debug-iphonesimulator/OpenFuse.app"
SIMCTL_CHILD_OPENFUSE_TRAKT_TOKEN=test SIMCTL_CHILD_OPENFUSE_JELLYFIN_TOKEN=test \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/launch.log" 2>&1 &
sleep 15
xcrun simctl io "$SIM" screenshot "$OUT/layout.png" >/dev/null 2>&1
YAVG=$(/opt/homebrew/bin/ffmpeg -hide_banner -nostats -i "$OUT/layout.png" \
  -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG -f null - 2>&1 \
  | sed -n 's/.*YAVG=\([0-9.]*\).*/\1/p' | head -1)
SIZE=$(stat -f%z "$OUT/layout.png")
YAVG="$YAVG" SIZE="$SIZE" python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
yavg = float(os.environ["YAVG"])
size = int(os.environ["SIZE"])
errors = []
if size < 30000:
    errors.append(f"screenshot too small {size}")
if yavg > 100:
    errors.append(f"screen appears blank/white YAVG={yavg}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: iPad layout rendered (YAVG={yavg:.1f}, {size} bytes)")
PY
