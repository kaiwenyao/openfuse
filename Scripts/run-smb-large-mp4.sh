#!/bin/bash
# M5ah: >8MB tail-moov HDR MP4; tail starts mid-mdat, moov scan required.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/smb-large-mp4"
SAMPLE=Fixtures/generated/openfuse-hdr-large.mp4
rm -rf "$OUT"; mkdir -p "$OUT/share/Movie" "$OUT/support"
if [[ ! -f "$SAMPLE" ]]; then
  /opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y -f lavfi \
    -i testsrc2=size=1920x1080:rate=24 -t 40 -c:v libx265 -pix_fmt yuv420p10le \
    -b:v 2500k -x265-params 'hdr-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)' \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
    -movflags +write_colr -an /tmp/openfuse-hdr-large.mp4
  python3 - "$SAMPLE" <<'PY'
from pathlib import Path
import sys
src=Path('/tmp/openfuse-hdr-large.mp4'); d=bytearray(src.read_bytes())
i=d.find(b'colr'); assert i>0 and d[i+4:i+8]==b'nclx'
d[i+8:i+12]=bytes([0,9,0,16]); Path(sys.argv[1]).write_bytes(d)
PY
fi
cp "$SAMPLE" "$OUT/share/Movie/OpenFuse.Large.mp4"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
build/impacket-venv/bin/smbserver.py -port 1445 -username test -password test -smb2support \
  SHARE "$OUT/share" >"$OUT/server.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if nc -z 127.0.0.1 1445 >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test \
  "$APP" --smb-server 127.0.0.1 --smb-port 1445 --smb-share SHARE --smb-user test \
  --smb-pass test --smb-name SMB --smb-scan --library-report "$OUT/library.json" \
  --quit-after 10 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
data = json.load(open(os.path.join(out, "library.json")))
versions = data["items"][0]["episodes"][0]["versions"] if data.get("items") else []
if not versions:
    errors.append("no versions")
else:
    if versions[0].get("resolution") != "1080p":
        errors.append(f"resolution {versions[0].get('resolution')}")
    if versions[0].get("dynamicRange") != "HDR10":
        errors.append(f"dynamicRange {versions[0].get('dynamicRange')}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: >8MB tail-moov HDR MP4 over SMB -> 1080p/HDR10")
PY
