#!/bin/bash
# M5w: local HDR10 metadata detection and library display.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/hdr-acceptance"
ROOT="$OUT/library"
rm -rf "$OUT"; mkdir -p "$ROOT/Movies"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
SAMPLE=Fixtures/generated/openfuse-hdr.mkv
if [[ ! -f "$SAMPLE" ]]; then
  /opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y -f lavfi \
    -i testsrc2=size=1920x1080:rate=24 -t 3 -c:v libx265 -pix_fmt yuv420p10le \
    -x265-params 'hdr-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)' \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -an /tmp/openfuse-hdr-tmp.mkv
  /opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y -i /tmp/openfuse-hdr-tmp.mkv -c copy \
    -bsf:v hevc_metadata=transfer_characteristics=16:colour_primaries=9:matrix_coefficients=9 \
    -color_trc smpte2084 -color_primaries bt2020 -colorspace bt2020nc "$SAMPLE"
fi
cp "$SAMPLE" "$ROOT/Movies/OpenFuse HDR (2026).mkv"
OPENFUSE_SUPPORT_DIR="$OUT/support" \
  "$APP" --scan-local "$ROOT" --library-report "$OUT/library.json" \
  --capture-ui "$OUT/library.png" --ui-after 6 --quit-after 8 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
data = json.load(open(os.path.join(out, "library.json")))
versions = data["items"][0]["episodes"][0]["versions"]
if not versions:
    errors.append("no versions")
else:
    if versions[0].get("dynamicRange") != "HDR10":
        errors.append(f"dynamicRange {versions[0].get('dynamicRange')}")
    if versions[0].get("resolution") != "1080p":
        errors.append(f"resolution {versions[0].get('resolution')}")
if not os.path.exists(os.path.join(out, "library.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: HDR10/1080p metadata stored and displayed")
PY
