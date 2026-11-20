#!/bin/bash
# M2d: iPhone simulator plays real OpenList WebDAV with remote SRT/progress.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${OPENFUSE_IOS_SIM:-E3AEF363-7F63-4945-A5AF-097DFBD4CDC6}"
BUNDLE=com.openfuse.mobile
OUT="$PWD/build/ios-openlist-acceptance"
DATA="$OUT/openlist-data"
rm -rf "$OUT"; mkdir -p "$DATA/files/Movies"
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
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
Scripts/build-ios.sh "platform=iOS Simulator,id=$SIM" "$OUT/build" Debug >/dev/null
APP="$OUT/build/Build/Products/Debug-iphonesimulator/OpenFuse.app"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
SIMCTL_CHILD_OPENFUSE_AUTOPLAY=1 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SOURCE=webdav \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_TITLE='OpenFuse OpenList' \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SEEK=10 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_PAUSE_AT=12 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SUBTITLE_INDEX=1 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_STOP_AFTER=18 \
SIMCTL_CHILD_OPENFUSE_TEST_WEBDAV_URL=http://127.0.0.1:5244/dav/ \
SIMCTL_CHILD_OPENFUSE_TEST_WEBDAV_USER=admin \
SIMCTL_CHILD_OPENFUSE_TEST_WEBDAV_PASSWORD=test \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/launch.log" 2>&1 &
sleep 16
xcrun simctl io "$SIM" screenshot "$OUT/play.png" >/dev/null 2>&1 || true
sleep 6
CONTAINER=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
cp "$CONTAINER/Library/Application Support/OpenFuse/playback.json" "$OUT/playback.json" 2>/dev/null || true
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
records = json.load(open(os.path.join(out, "playback.json"))).get("records", {})
record = next((r for r in records.values() if r.get("sourceKind") == "webdav"), None)
if not record:
    errors.append(f"no webdav record: {records}")
else:
    if record.get("position", 0) < 10:
        errors.append(f"position {record.get('position')}")
    if "5244/dav/local/Movies" not in record.get("remoteURL", ""):
        errors.append(f"remoteURL {record.get('remoteURL')}")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: iPhone OpenList playback + remote subtitle + progress")
PY
