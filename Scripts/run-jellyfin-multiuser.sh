#!/bin/bash
# M2h: Jellyfin multi-user progress isolation.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/jellyfin-multiuser"
ROOT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$OUT/support2"
if [[ ! -f "$ROOT/config/config/system.xml" ]]; then
  echo "run Scripts/run-real-jellyfin.sh first" >&2
  exit 2
fi
docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true
docker run -d --name openfuse-jellyfin -p 8096:8096 \
  -v "$ROOT/config:/config" -v "$ROOT/cache:/cache" -v "$ROOT/media:/media" \
  jellyfin/jellyfin:latest >/dev/null
trap 'docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true' EXIT
for _ in {1..60}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public 2>/dev/null | grep -q '"Id"'; then break; fi
  sleep 1
done
H='Authorization: MediaBrowser Client="OpenFuse", Device="Mac", DeviceId="admin", Version="1.0"'
AUTH1=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H" -H 'Content-Type: application/json' -d '{"Username":"test","Pw":"test"}')
TOKEN1=$(echo "$AUTH1" | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
USER1=$(echo "$AUTH1" | python3 -c 'import json,sys;print(json.load(sys.stdin)["User"]["Id"])')
H2='Authorization: MediaBrowser Client="OpenFuse", Device="Mac", DeviceId="u2", Version="1.0"'
AUTH2=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H2" -H 'Content-Type: application/json' -d '{"Username":"test2","Pw":"test2"}')
if ! echo "$AUTH2" | grep -q '"AccessToken"'; then
  curl -sS -o /dev/null -X POST http://127.0.0.1:8096/Users/New \
    -H "Authorization: MediaBrowser Token=\"$TOKEN1\"" -H 'Content-Type: application/json' \
    -d '{"Name":"test2","Password":"test2"}'
  AUTH2=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H2" -H 'Content-Type: application/json' -d '{"Username":"test2","Pw":"test2"}')
fi
TOKEN2=$(echo "$AUTH2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
USER2=$(echo "$AUTH2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["User"]["Id"])')
curl -sS -o /dev/null -X POST "http://127.0.0.1:8096/Users/$USER2/Configuration" \
  -H "Authorization: MediaBrowser Token=\"$TOKEN1\"" -H 'Content-Type: application/json' \
  -d '{"EnableLocalPassword":true}'
IID=$(curl -sS 'http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Movie' \
  -H "Authorization: MediaBrowser Token=\"$TOKEN1\"" \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print(next(i["Id"] for i in d["Items"] if i["Name"]=="OpenFuse Jellyfin"))')
curl -sS -o /dev/null -X DELETE "http://127.0.0.1:8096/Users/$USER1/PlayedItems/$IID" \
  -H "Authorization: MediaBrowser Token=\"$TOKEN1\""
Scripts/build-app.sh >/dev/null
swift test >/dev/null
OPENFUSE_SUPPORT_DIR="$OUT/support2" \
OPENFUSE_JELLYFIN_PASSWORD=test2 OPENFUSE_JELLYFIN_TOKEN="$TOKEN2" \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test2 --jellyfin-pass test2 \
  --jellyfin-name Jellyfin2 --jellyfin-scan --library-report "$OUT/library.json" \
  --quit-after 8 >"$OUT/scan.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
print(next(i["episodes"][0]["id"] for i in data["items"] if i["title"] == "OpenFuse Jellyfin"))
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support2" \
OPENFUSE_JELLYFIN_PASSWORD=test2 OPENFUSE_JELLYFIN_TOKEN="$TOKEN2" \
  "$APP" --library-play "$EPISODE" --seek 10 --freeze-at 11 \
  --report "$OUT/play.json" --capture-after 8 --quit-after 12 >"$OUT/play.log" 2>&1 || true
sleep 2
curl -sS "http://127.0.0.1:8096/Users/$USER1/Items/$IID" \
  -H "Authorization: MediaBrowser Token=\"$TOKEN1\"" >"$OUT/user1.json"
curl -sS "http://127.0.0.1:8096/Users/$USER2/Items/$IID" \
  -H "Authorization: MediaBrowser Token=\"$TOKEN2\"" >"$OUT/user2.json"
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 10:
    errors.append(f"user2 position {play.get('position')}")
u1 = json.load(open(os.path.join(out, "user1.json"))).get("UserData", {})
u2 = json.load(open(os.path.join(out, "user2.json"))).get("UserData", {})
if u2.get("PlaybackPositionTicks", 0) < 100_000_000:
    errors.append(f"user2 server {u2}")
if u1.get("PlaybackPositionTicks", 0) != 0:
    errors.append(f"user1 contaminated {u1}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Jellyfin multi-user progress isolated")
PY
