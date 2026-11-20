#!/bin/bash
# M5ab: HDR passthrough on an EDR-capable display.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/hdr-passthrough"
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
if float(data.get("screenEDR", 0)) <= 1:
    errors.append(f"screenEDR {data.get('screenEDR')}")
if data.get("targetColorspaceHint") != "yes":
    errors.append(f"targetColorspaceHint {data.get('targetColorspaceHint')}")
if data.get("videoPrimaries") != "bt.2020" or data.get("videoGamma") != "pq":
    errors.append(f"source colour {data.get('videoPrimaries')}/{data.get('videoGamma')}")
out_params = data.get("videoOutParams") or ""
if '"light":"display"' not in out_params:
    errors.append("video-out-params light != display")
if '"primaries":"bt.2020"' not in out_params or '"gamma":"pq"' not in out_params:
    errors.append("video-out-params not bt.2020/pq")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: EDR display + target-colorspace-hint + PQ/bt.2020 display output")
PY
