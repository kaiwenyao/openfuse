#!/bin/bash
# Real OpenList (Docker) WebDAV scan/play/Range acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/openlist"
DATA="$OUT/data"
rm -rf "$OUT"; mkdir -p "$DATA/files/Movies" "$OUT/support"
cp Fixtures/mobile/openfuse-mobile.mp4 "$DATA/files/Movies/OpenFuse OpenList.mp4"
cp Fixtures/mobile/openfuse-mobile.zh-Hans.srt "$DATA/files/Movies/OpenFuse OpenList.zh-Hans.srt"
docker rm -f openfuse-openlist >/dev/null 2>&1 || true
docker run -d --name openfuse-openlist -p 5244:5244 \
  -e OPENLIST_ADMIN_PASSWORD=test -v "$DATA:/opt/openlist/data" \
  openlistteam/openlist:latest >/dev/null
trap 'docker rm -f openfuse-openlist >/dev/null 2>&1 || true' EXIT
for _ in {1..60}; do
  if curl -sS --max-time 1 http://127.0.0.1:5244/api/public/settings >/dev/null 2>&1; then break; fi
  sleep 0.5
done
TOKEN=$(curl -sS -X POST http://127.0.0.1:5244/api/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"test"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["token"])')
curl -sS -X POST http://127.0.0.1:5244/api/admin/storage/create \
  -H "Authorization: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"mount_path":"/local","driver":"Local","addition":"{\"root_folder_path\":\"/opt/openlist/data/files\"}","order":0,"remark":"fixture"}' \
  >"$OUT/storage.json"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_WEBDAV_USER=admin OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url http://127.0.0.1:5244/dav/ --webdav-user admin --webdav-pass test \
  --webdav-name OpenList --webdav-scan --library-report "$OUT/library.json" \
  --quit-after 8 >"$OUT/scan.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
print(data["items"][0]["episodes"][0]["id"])
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_WEBDAV_USER=admin OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --library-play "$EPISODE" --seek 10 --freeze-at 11 \
  --capture "$OUT/play.png" --capture-after 8 --report "$OUT/play.json" \
  --quit-after 10 >"$OUT/play.log" 2>&1 || true
sleep 0.5
RANGE=$(curl -sS -o /dev/null -w '%{http_code}' -u admin:test \
  -H 'Range: bytes=0-1023' 'http://127.0.0.1:5244/dav/local/Movies/OpenFuse%20OpenList.mp4')
python3 - "$OUT" "$RANGE" <<'PY'
import json, os, sys
out, range_status = sys.argv[1], sys.argv[2]
errors = []
library = json.load(open(os.path.join(out, "library.json")))
versions = library["items"][0]["episodes"][0]["versions"] if library.get("items") else []
if not versions:
    errors.append("no OpenList versions")
elif versions[0].get("resolution") != "1080p":
    errors.append(f"resolution {versions[0].get('resolution')}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 10:
    errors.append(f"position {play.get('position')}")
if not str(play.get("selectedSubtitle", "")).startswith("remote:"):
    errors.append(f"subtitle {play.get('selectedSubtitle')}")
if range_status != "206":
    errors.append(f"Range HTTP {range_status}")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: real OpenList WebDAV scan/play/Range/subtitle")
PY
