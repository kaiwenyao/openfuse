#!/bin/bash
# M3q: pure Swift MKV header parser (used on iOS/tvOS/visionOS).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/mkv-header"
rm -rf "$OUT"; mkdir -p "$OUT/webdav/Movie"
cp Fixtures/generated/openfuse-hdr.mkv "$OUT/webdav/Movie/OpenFuse.HDR.mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/webdav_fixture.py --root "$OUT/webdav" --port 8122 --log "$OUT/webdav.log" >"$OUT/webdav.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test http://127.0.0.1:8122/dav/ >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_MKV_HEADER=1 OPENFUSE_WEBDAV_USER=test OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url http://127.0.0.1:8122/dav/ --webdav-user test --webdav-pass test \
  --webdav-name WebDAV --webdav-scan --library-report "$OUT/library.json" \
  --quit-after 8 >"$OUT/app.log" 2>&1 || true
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
print("PASS: MKV header parser yields 1080p/HDR10 from 2MB Range")
PY
