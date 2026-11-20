#!/bin/bash
# M6a: visionOS immersive space opens; simulator VideoMaterial limitation noted.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${OPENFUSE_VISION_SIM:-E3993B10-EDE9-42F3-87FE-E1D6F61D788A}"
BUNDLE=com.openfuse.vision
OUT="$PWD/build/vision-immersive"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodegen generate --spec project.yml >/dev/null
xcodebuild -project OpenFuseMobile.xcodeproj -scheme OpenFuseVision -configuration Debug \
  -destination "platform=visionOS Simulator,id=$SIM" -derivedDataPath "$OUT/derived" \
  CODE_SIGNING_ALLOWED=NO build >"$OUT/build.log" 2>&1
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
APP="$OUT/derived/Build/Products/Debug-xrsimulator/OpenFuse.app"
python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
plist = plistlib.load(open(sys.argv[1], "rb"))
assert plist.get("UIApplicationSceneManifest", {}).get("UIApplicationSupportsMultipleScenes") is True
print("multi-scene ok")
PY
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SIMCTL_CHILD_OPENFUSE_AUTOPLAY=1 SIMCTL_CHILD_OPENFUSE_IMMERSIVE=1 \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/launch.log" 2>&1 &
sleep 14
xcrun simctl io "$SIM" screenshot "$OUT/immersive.png" >/dev/null 2>&1 || true
xcrun simctl spawn "$SIM" log show --start "$START" --style compact \
  --predicate 'process == "OpenFuse"' 2>/dev/null >"$OUT/log.txt" || true
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
SIMCTL_CHILD_OPENFUSE_AUTOPLAY=1 SIMCTL_CHILD_OPENFUSE_IMMERSIVE=1 \
SIMCTL_CHILD_OPENFUSE_IMMERSIVE_AUTOCLOSE=6 \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/autoclose.log" 2>&1 &
sleep 16
DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
cp "$DATA/Library/Application Support/OpenFuse/playback.json" "$OUT/playback.json" 2>/dev/null || true
xcrun simctl io "$SIM" screenshot "$OUT/autoclose.png" >/dev/null 2>&1 || true
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
if not os.path.exists(os.path.join(out, "immersive.png")):
    errors.append("screenshot missing")
log = open(os.path.join(out, "log.txt"), encoding="utf-8", errors="replace").read()
if "Unable to open an immersive space" in log:
    errors.append("immersive space rejected")
playback = json.load(open(os.path.join(out, "playback.json")))
records = playback.get("records", {})
if not records:
    errors.append("immersive progress not written")
elif not any(record.get("position", 0) > 0 for record in records.values()):
    errors.append(f"position not advanced: {records}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: immersive opened and auto-close wrote resume progress")
PY
