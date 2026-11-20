#!/bin/bash
# M2f: iPhone plays a real Jellyfin MKV through HLS transcode.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${OPENFUSE_IOS_SIM:-E3AEF363-7F63-4945-A5AF-097DFBD4CDC6}"
BUNDLE=com.openfuse.mobile
OUT="$PWD/build/ios-jellyfin-hls"
ROOT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$OUT"
if [[ ! -f "$ROOT/config/config/system.xml" ]]; then
  echo "run Scripts/run-real-jellyfin.sh and add OpenFuse MKV first" >&2
  exit 2
fi
mkdir -p "$ROOT/media/Movies"
cp Fixtures/generated/openfuse-fixture.mkv "$ROOT/media/Movies/OpenFuse MKV.mkv"
docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true
docker run -d --name openfuse-jellyfin -p 8096:8096 \
  -v "$ROOT/config:/config" -v "$ROOT/cache:/cache" -v "$ROOT/media:/media" \
  jellyfin/jellyfin:latest >/dev/null
trap 'docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true' EXIT
for _ in {1..60}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public 2>/dev/null | grep -q '"Id"'; then break; fi
  sleep 1
done
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
Scripts/build-ios.sh "platform=iOS Simulator,id=$SIM" "$OUT/build" Debug >/dev/null
APP="$OUT/build/Build/Products/Debug-iphonesimulator/OpenFuse.app"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
SIMCTL_CHILD_OPENFUSE_AUTOPLAY=1 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SOURCE=jellyfin \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_TITLE='OpenFuse MKV' \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SEEK=10 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_PAUSE_AT=12 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SUBTITLE_INDEX=1 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_STOP_AFTER=20 \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_URL=http://127.0.0.1:8096 \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_USER=test \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_PASSWORD=test \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/launch.log" 2>&1 &
sleep 24
xcrun simctl io "$SIM" screenshot "$OUT/play.png" >/dev/null 2>&1 || true
sleep 6
CONTAINER=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
cp "$CONTAINER/Library/Application Support/OpenFuse/playback.json" "$OUT/playback.json" 2>/dev/null || true
docker logs openfuse-jellyfin >"$OUT/jellyfin.log" 2>&1 || true
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
records = json.load(open(os.path.join(out, "playback.json"))).get("records", {})
record = next((r for r in records.values() if r.get("sourceKind") == "jellyfin"), None)
if not record:
    errors.append(f"no jellyfin record {records}")
else:
    if record.get("position", 0) < 10:
        errors.append(f"position {record.get('position')}")
    if ".m3u8" not in record.get("remoteURL", ""):
        errors.append(f"not HLS {record.get('remoteURL')}")
log = open(os.path.join(out, "jellyfin.log"), encoding="utf-8", errors="replace").read()
if "-f hls" not in log:
    errors.append("Jellyfin did not start HLS transcode")
if "-maxrate 8000000" not in log:
    errors.append("HLS transcode not using 8Mbps")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: iPhone Jellyfin MKV -> HLS transcode + position")
PY
