#!/bin/bash
# M4u: Mac -> HTTP progress service -> iPhone resume.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
SIM="${OPENFUSE_IOS_SIM:-E3AEF363-7F63-4945-A5AF-097DFBD4CDC6}"
BUNDLE=com.openfuse.mobile
OUT="$PWD/build/cross-device-sync"
ROOT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$OUT/mac-support"
if [[ ! -f "$ROOT/config/config/system.xml" ]]; then
  echo "run Scripts/run-real-jellyfin.sh first" >&2
  exit 2
fi
lsof -ti tcp:8130 | xargs -r kill 2>/dev/null || true
docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true
python3 Tools/progress_sync_fixture.py --port 8130 --log "$OUT/sync.log" --token sync-test >"$OUT/sync.out" 2>&1 &
SYNCPID=$!
docker run -d --name openfuse-jellyfin -p 8096:8096 \
  -v "$ROOT/config:/config" -v "$ROOT/cache:/cache" -v "$ROOT/media:/media" \
  jellyfin/jellyfin:latest >/dev/null
trap 'kill $SYNCPID >/dev/null 2>&1 || true; docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true' EXIT
for _ in {1..60}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public 2>/dev/null | grep -q '"Id"'; then break; fi
  sleep 1
done
H='Authorization: MediaBrowser Client="OpenFuse", Device="Mac", DeviceId="admin", Version="1.0"'
TOKEN=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H" \
  -H 'Content-Type: application/json' -d '{"Username":"test","Pw":"test"}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
Scripts/build-app.sh >/dev/null
swift test >/dev/null
pkill -f "OpenFuse.app/Contents/MacOS/OpenFuse" 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$OUT/mac-support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_PASSWORD=test OPENFUSE_JELLYFIN_TOKEN="$TOKEN" \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test --jellyfin-pass test \
  --jellyfin-name Jellyfin --jellyfin-scan --library-report "$OUT/mac-library.json" \
  --quit-after 8 >"$OUT/mac-scan.log" 2>&1 || true
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/mac-library.json"))
print(next(i["episodes"][0]["id"] for i in data["items"] if i["title"] == "OpenFuse Jellyfin"))
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/mac-support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_PASSWORD=test OPENFUSE_JELLYFIN_TOKEN="$TOKEN" \
  "$APP" --library-play "$EPISODE" --seek 10 --freeze-at 11 \
  --report "$OUT/mac-play.json" --capture-after 8 --quit-after 12 \
  >"$OUT/mac-play.log" 2>&1 || true
OPENFUSE_SUPPORT_DIR="$OUT/mac-support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_TOKEN="$TOKEN" OPENFUSE_SYNC_URL=http://127.0.0.1:8130/progress \
OPENFUSE_SYNC_TOKEN=sync-test "$APP" --sync-progress --quit-after 5 >"$OUT/mac-sync.log" 2>&1 || true
Scripts/build-ios.sh "platform=iOS Simulator,id=$SIM" "$OUT/ios-build" Debug >/dev/null
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$OUT/ios-build/Build/Products/Debug-iphonesimulator/OpenFuse.app"
SIMCTL_CHILD_OPENFUSE_AUTOPLAY=1 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SOURCE=jellyfin \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_TITLE='OpenFuse Jellyfin' \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_PAUSE_AT=13 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_STOP_AFTER=18 \
SIMCTL_CHILD_OPENFUSE_REPORT_RESUME=1 \
SIMCTL_CHILD_OPENFUSE_SYNC_URL=http://127.0.0.1:8130/progress \
SIMCTL_CHILD_OPENFUSE_SYNC_TOKEN=sync-test \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_URL=http://127.0.0.1:8096 \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_USER=test \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_PASSWORD=test \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/ios.log" 2>&1 &
sleep 9
xcrun simctl io "$SIM" screenshot "$OUT/ios-resume.png" >/dev/null 2>&1 || true
sleep 8
DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
cp "$DATA/Library/Application Support/OpenFuse/autoplay-resume.json" "$OUT/ios-resume.json" 2>/dev/null || true
cp "$DATA/Library/Application Support/OpenFuse/playback.json" "$OUT/ios-playback.json" 2>/dev/null || true
NOAUTH=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8130/progress || true)
if [[ "$NOAUTH" != "401" ]]; then
  echo "FAIL: sync service accepted request without token ($NOAUTH)" >&2
  exit 1
fi
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
mac = json.load(open(os.path.join(out, "mac-play.json")))
if mac.get("position", 0) < 10:
    errors.append(f"mac position {mac.get('position')}")
resume = json.load(open(os.path.join(out, "ios-resume.json")))
if resume.get("resume", 0) < 10:
    errors.append(f"iphone resume {resume}")
sync = open(os.path.join(out, "sync.log"), encoding="utf-8", errors="replace").read()
if '"method": "POST"' not in sync:
    errors.append("no POST to sync service")
if not os.path.exists(os.path.join(out, "ios-resume.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: Mac pushed and iPhone resumed at {resume['resume']:.2f}s")
PY
