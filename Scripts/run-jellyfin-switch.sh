#!/bin/bash
# M4x: switch a Jellyfin source from test to test2 without stale library rows.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/jellyfin-switch"
ROOT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$OUT/support"
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
TOKEN1=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H" \
  -H 'Content-Type: application/json' -d '{"Username":"test","Pw":"test"}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
H2='Authorization: MediaBrowser Client="OpenFuse", Device="Mac", DeviceId="u2", Version="1.0"'
A2=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H2" \
  -H 'Content-Type: application/json' -d '{"Username":"test2","Pw":"test2"}')
TOKEN2=$(echo "$A2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
USER2=$(echo "$A2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["User"]["Id"])')
Scripts/build-app.sh >/dev/null
swift test >/dev/null
pkill -f "OpenFuse.app/Contents/MacOS/OpenFuse" 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_JELLYFIN_PASSWORD=test OPENFUSE_JELLYFIN_TOKEN="$TOKEN1" \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test --jellyfin-pass test \
  --jellyfin-name Jellyfin --jellyfin-scan --library-report "$OUT/before.json" \
  --quit-after 8 >"$OUT/before.log" 2>&1 || true
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_JELLYFIN_TOKEN="$TOKEN1" OPENFUSE_JELLYFIN_PASSWORD=test2 \
  "$APP" --jellyfin-switch-user test2 --jellyfin-switch-password test2 \
  --library-report "$OUT/after.json" --quit-after 12 >"$OUT/after.log" 2>&1 || true
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/after.json"))
print(next(i["episodes"][0]["id"] for i in data["items"] if i["title"] == "OpenFuse Jellyfin"))
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_JELLYFIN_TOKEN="$TOKEN2" OPENFUSE_JELLYFIN_PASSWORD=test2 \
  "$APP" --library-play "$EPISODE" --seek 10 --freeze-at 11 \
  --report "$OUT/play.json" --capture-after 8 --quit-after 12 >"$OUT/play.log" 2>&1 || true
cat "$OUT/support/jellyfin-sources.json" >"$OUT/sources.json"
USER2="$USER2" TOKEN2="$TOKEN2" python3 - "$OUT" <<'PY'
import json, os, sys, urllib.request
out = sys.argv[1]
errors = []
sources = json.load(open(os.path.join(out, "sources.json"))).get("sources", [])
if len(sources) != 1 or sources[0].get("username") != "test2":
    errors.append(f"sources {sources}")
after = json.load(open(os.path.join(out, "after.json")))
if after.get("rawWorks") != 2:
    errors.append(f"after works {after.get('rawWorks')}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 10:
    errors.append(f"position {play.get('position')}")
request = urllib.request.Request(
    f"http://127.0.0.1:8096/Users/{os.environ['USER2']}/Items/c9a8049da54e0f1e4ffbf6cce67cee71",
    headers={"Authorization": f"MediaBrowser Token=\"{os.environ['TOKEN2']}\""},
)
user = json.load(urllib.request.urlopen(request)).get("UserData", {})
if user.get("PlaybackPositionTicks", 0) < 100_000_000:
    errors.append(f"server userdata {user}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Jellyfin user switched to test2, library clean, progress written")
PY
