#!/bin/bash
# M6i: tvOS launches bundled sample into TVPlayerView.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${OPENFUSE_TV_SIM:-4DD8F41F-EB8C-4E5E-BABF-99A2F650F74E}"
OUT="$PWD/build/tvos-playback"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -project OpenFuseMobile.xcodeproj -scheme OpenFuseTV -configuration Debug \
  -destination "platform=tvOS Simulator,id=$SIM" -derivedDataPath "$OUT/build" \
  CODE_SIGNING_ALLOWED=NO build >"$OUT/build.log" 2>&1
APP="$OUT/build/Build/Products/Debug-appletvsimulator/OpenFuse.app"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl terminate "$SIM" com.openfuse.tv 2>/dev/null || true
xcrun simctl uninstall "$SIM" com.openfuse.tv 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
SIMCTL_CHILD_OPENFUSE_AUTOPLAY=1 SIMCTL_CHILD_\
SIMCTL_CHILD_OPENFUSE_JELLYFIN_TOKEN=test \
  xcrun simctl launch --console "$SIM" com.openfuse.tv >"$OUT/launch.log" 2>&1 &
sleep 10
xcrun simctl io "$SIM" screenshot "$OUT/play.png" >/dev/null 2>&1
YAVG=$(/opt/homebrew/bin/ffmpeg -hide_banner -nostats -i "$OUT/play.png" \
  -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG -f null - 2>&1 \
  | sed -n 's/.*YAVG=\([0-9.]*\).*/\1/p' | head -1)
SIZE=$(stat -f%z "$OUT/play.png")
YAVG="$YAVG" SIZE="$SIZE" python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
yavg = float(os.environ["YAVG"])
size = int(os.environ["SIZE"])
errors = []
if size < 200000:
    errors.append(f"screenshot too small {size}")
if yavg > 120:
    errors.append(f"screen appears blank/white YAVG={yavg}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: tvOS played bundled sample (YAVG={yavg:.1f}, {size} bytes)")
PY
