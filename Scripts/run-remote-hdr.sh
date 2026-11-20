#!/bin/bash
# M5x: Jellyfin VideoRange + WebDAV ffprobe HDR metadata.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/remote-hdr"
rm -rf "$OUT"; mkdir -p "$OUT/webdav/Movie" "$OUT/support-jf" "$OUT/support-webdav"
cp Fixtures/generated/openfuse-hdr.mkv "$OUT/webdav/Movie/OpenFuse.HDR.mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/jellyfin_fixture.py --port 8096 --mobile-sample >"$OUT/jf.out" 2>&1 &
JPID=$!
python3 Tools/webdav_fixture.py --root "$OUT/webdav" --port 8122 --log "$OUT/webdav.log" >"$OUT/webdav.out" 2>&1 &
WPID=$!
trap 'kill "$JPID" "$WPID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public >/dev/null 2>&1 \
     && curl -sS --max-time 1 -u test:test http://127.0.0.1:8122/dav/ >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support-jf" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_PASSWORD=test OPENFUSE_JELLYFIN_TOKEN=jf-test-token \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test --jellyfin-pass test \
  --jellyfin-name Jellyfin --jellyfin-scan --library-report "$OUT/jf.json" \
  --quit-after 8 >"$OUT/jf-app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support-webdav" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_WEBDAV_USER=test OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url http://127.0.0.1:8122/dav/ --webdav-user test --webdav-pass test \
  --webdav-name WebDAV --webdav-scan --library-report "$OUT/webdav.json" \
  --capture-ui "$OUT/webdav.png" --ui-after 7 --quit-after 9 >"$OUT/webdav-app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
jf = json.load(open(os.path.join(out, "jf.json")))
versions = jf["items"][0]["episodes"][0]["versions"]
if not versions or versions[0].get("dynamicRange") != "HDR10":
    errors.append(f"jellyfin HDR {versions}")
webdav = json.load(open(os.path.join(out, "webdav.json")))
versions = webdav["items"][0]["episodes"][0]["versions"]
if not versions or versions[0].get("dynamicRange") != "HDR10":
    errors.append(f"webdav HDR {versions}")
if not os.path.exists(os.path.join(out, "webdav.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Jellyfin VideoRange and WebDAV ffprobe both report HDR10")
PY
