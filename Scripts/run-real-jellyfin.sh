#!/bin/bash
# Real Jellyfin 12 (Docker) startup/library/scan/play acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$OUT/config" "$OUT/cache" "$OUT/media/Movies" "$OUT/support"
cp Fixtures/mobile/openfuse-mobile.mp4 "$OUT/media/Movies/OpenFuse Jellyfin.mp4"
cp Fixtures/mobile/openfuse-mobile.zh-Hans.srt "$OUT/media/Movies/OpenFuse Jellyfin.zh-Hans.srt"
docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true
docker run -d --name openfuse-jellyfin -p 8096:8096 \
  -v "$OUT/config:/config" -v "$OUT/cache:/cache" -v "$OUT/media:/media" \
  jellyfin/jellyfin:latest >/dev/null
trap 'docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true' EXIT
for _ in {1..60}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public 2>/dev/null | grep -q '"Id"'; then break; fi
  sleep 1
done
H='Authorization: MediaBrowser Client="OpenFuse", Device="Mac", DeviceId="setup", Version="1.0"'
curl -sS -o /dev/null -X POST http://127.0.0.1:8096/Startup/Configuration -H "$H" \
  -H 'Content-Type: application/json' \
  -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
curl -sS -o /dev/null http://127.0.0.1:8096/Startup/User -H "$H"
curl -sS -o /dev/null -X POST http://127.0.0.1:8096/Startup/User -H "$H" \
  -H 'Content-Type: application/json' -d '{"Name":"test","Password":"test"}'
curl -sS -o /dev/null -X POST http://127.0.0.1:8096/Startup/Complete -H "$H"
docker exec -u 0 openfuse-jellyfin sed -i 's#<MinResumeDurationSeconds>300</MinResumeDurationSeconds>#<MinResumeDurationSeconds>0</MinResumeDurationSeconds>#' /config/config/system.xml
docker restart openfuse-jellyfin >/dev/null
for _ in {1..30}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public 2>/dev/null | grep -q '"Id"'; then break; fi
  sleep 1
done
sleep 1
AUTH=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H" \
  -H 'Content-Type: application/json' -d '{"Username":"test","Pw":"test"}')
TOKEN=$(echo "$AUTH" | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
TH="Authorization: MediaBrowser Token=\"$TOKEN\""
curl -sS -o /dev/null -X POST \
  'http://127.0.0.1:8096/Library/VirtualFolders?name=Movies&collectionType=movies&paths=/media/Movies&refreshLibrary=true' \
  -H "$TH"
for _ in {1..40}; do
  COUNT=$(curl -sS 'http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Movie' -H "$TH" \
    | python3 -c 'import json,sys;print(len(json.load(sys.stdin).get("Items",[])))' 2>/dev/null || echo 0)
  if [[ "$COUNT" -ge 1 ]]; then break; fi
  sleep 1
done
Scripts/build-app.sh >/dev/null
swift test >/dev/null
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_PASSWORD=test OPENFUSE_JELLYFIN_TOKEN="$TOKEN" \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test --jellyfin-pass test \
  --jellyfin-name Jellyfin --jellyfin-scan --library-report "$OUT/library.json" \
  --quit-after 8 >"$OUT/scan.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
print(data["items"][0]["episodes"][0]["id"])
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_PASSWORD=test OPENFUSE_JELLYFIN_TOKEN="$TOKEN" \
  "$APP" --library-play "$EPISODE" --seek 10 --freeze-at 11 \
  --capture "$OUT/play.png" --capture-after 8 --report "$OUT/play.json" \
  --quit-after 12 >"$OUT/play.log" 2>&1 || true
sleep 2
curl -sS 'http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Movie' -H "$TH" \
  >"$OUT/items.json"
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
library = json.load(open(os.path.join(out, "library.json")))
versions = library["items"][0]["episodes"][0]["versions"] if library.get("items") else []
if not versions:
    errors.append("no Jellyfin versions")
elif versions[0].get("resolution") != "1080p":
    errors.append(f"resolution {versions[0].get('resolution')}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 10:
    errors.append(f"position {play.get('position')}")
if play.get("audioChannels") != "6":
    errors.append(f"channels {play.get('audioChannels')}")
if not str(play.get("selectedSubtitle", "")).startswith("mpv:"):
    errors.append(f"subtitle {play.get('selectedSubtitle')}")
items = json.load(open(os.path.join(out, "items.json"))).get("Items", [])
user_data = items[0].get("UserData", {}) if items else {}
if user_data.get("PlaybackPositionTicks", 0) < 100_000_000:
    errors.append(f"server position {user_data}")
if user_data.get("Played") is True:
    errors.append(f"server marked played at 55%: {user_data}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: real Jellyfin scan/play/seek/subtitle/server progress")
PY
