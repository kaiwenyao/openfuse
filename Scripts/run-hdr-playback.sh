#!/bin/bash
# M5y: HDR10 tone-mapped playback properties on Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/hdr-playback"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test "$APP" \
  --open Fixtures/generated/openfuse-hdr.mkv --freeze-at 1.5 \
  --capture "$OUT/play.png" --capture-after 8 --report "$OUT/play.json" \
  --quit-after 10 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
data = json.load(open(os.path.join(out, "play.json")))
checks = {
    "videoPrimaries": "bt.2020",
    "videoGamma": "pq",
    "toneMapping": "spline",
    "hdrComputePeak": "yes",
}
for key, expected in checks.items():
    if data.get(key) != expected:
        errors.append(f"{key}={data.get(key)} expected {expected}")
if not data.get("videoSigPeak"):
    errors.append("videoSigPeak missing")
if data.get("position", 0) < 1.0:
    errors.append(f"position {data.get('position')}")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: HDR10 decoded (bt.2020/pq), spline tone mapping, sig-peak present")
PY
