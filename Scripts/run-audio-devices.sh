#!/bin/bash
# M5ac: CoreAudio output device enumeration and mpv device selection.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
PROBE=".build/debug/openfuse-probe"
OUT="$PWD/build/audio-devices"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
swift build --product openfuse-probe >/dev/null
swift test >/dev/null
"$PROBE" audio-devices unused >"$OUT/devices.json"
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_AUDIO_DEVICE=coreaudio/BuiltInSpeakerDevice \
  "$APP" --open Fixtures/generated/openfuse-fixture.mkv --freeze-at 2 \
  --report "$OUT/play.json" --capture-after 5 --quit-after 7 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
devices = json.load(open(os.path.join(out, "devices.json")))
if not any("BuiltInSpeakerDevice" in item.get("id", "") for item in devices):
    errors.append(f"built-in speaker missing: {devices}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("audioDevice") != "coreaudio/BuiltInSpeakerDevice":
    errors.append(f"selected {play.get('audioDevice')}")
if play.get("audioDeviceActive") != "coreaudio/BuiltInSpeakerDevice":
    errors.append(f"active {play.get('audioDeviceActive')}")
if play.get("currentAO") != "coreaudio":
    errors.append(f"AO {play.get('currentAO')}")
if play.get("audioChannels") != "6":
    errors.append(f"channels {play.get('audioChannels')}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: CoreAudio devices enumerated and mpv switched to built-in speaker")
PY
