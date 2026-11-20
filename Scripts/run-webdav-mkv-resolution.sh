#!/bin/bash
# M3m: remote MKV resolution via authenticated ffprobe + 1080p filter.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/webdav-mkv-resolution"
ROOT="$OUT/root"
rm -rf "$OUT"; mkdir -p "$ROOT/Movie"
cp Fixtures/generated/openfuse-fixture.mkv "$ROOT/Movie/OpenFuse.Remote.mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/webdav_fixture.py --root "$ROOT" --port 8122 --log "$OUT/webdav.log" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test "http://127.0.0.1:8122/dav/" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_WEBDAV_USER=test OPENFUSE_WEBDAV_PASSWORD=test "$APP" \
  --webdav-url http://127.0.0.1:8122/dav/ --webdav-user test --webdav-pass test \
  --webdav-name WebDAV --webdav-scan --library-report "$OUT/library.json" \
  --capture-ui "$OUT/library.png" --ui-after 8 --quit-after 14 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --library-resolution hd1080 \
  --library-report "$OUT/filter.json" --quit-after 4 >"$OUT/filter.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
data = json.load(open(os.path.join(out, "library.json")))
versions = data["items"][0]["episodes"][0]["versions"]
if not versions or versions[0].get("resolution") != "1080p":
    errors.append(f"resolution {versions}")
if "1080p" not in versions[0].get("name", ""):
    errors.append(f"name {versions[0].get('name')}")
filtered = json.load(open(os.path.join(out, "filter.json")))
if "OpenFuse Remote" not in filtered.get("visible", []):
    errors.append(f"1080p filter visible {filtered.get('visible')}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: remote WebDAV MKV 1080p, version name, 1080p filter")
PY
