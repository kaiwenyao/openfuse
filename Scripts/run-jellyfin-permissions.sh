#!/bin/bash
# M2i: Jellyfin per-user library permission enforcement.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/jellyfin-permissions"
ROOT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$OUT"
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
AUTH=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H" -H 'Content-Type: application/json' -d '{"Username":"test","Pw":"test"}')
TOKEN=$(echo "$AUTH" | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
USER2=390f2c13d06c42879983e371bb125537
TH="Authorization: MediaBrowser Token=\"$TOKEN\""
curl -sS "http://127.0.0.1:8096/Users/$USER2" -H "$TH" >"$OUT/user2.json"
python3 - "$OUT" <<'PY'
import json, sys
u=json.load(open(f"{sys.argv[1]}/user2.json")); p=u["Policy"]
p["EnableAllFolders"]=False; p["EnabledFolders"]=[]
json.dump(p,open(f"{sys.argv[1]}/restricted.json","w"))
p["EnableAllFolders"]=True; p["EnabledFolders"]=[]
json.dump(p,open(f"{sys.argv[1]}/allowed.json","w"))
PY
H2='Authorization: MediaBrowser Client="OpenFuse", Device="Mac", DeviceId="u2", Version="1.0"'
login2() {
  curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H2" \
    -H 'Content-Type: application/json' -d '{"Username":"test2","Pw":"test2"}' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])'
}
curl -sS -o /dev/null -X POST "http://127.0.0.1:8096/Users/$USER2/Policy" -H "$TH" \
  -H 'Content-Type: application/json' --data @"$OUT/restricted.json"
TOKEN2=$(login2)
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT/restricted-support" "$OUT/allowed-support"; mkdir -p "$OUT/restricted-support" "$OUT/allowed-support"
OPENFUSE_SUPPORT_DIR="$OUT/restricted-support" \
OPENFUSE_JELLYFIN_PASSWORD=test2 OPENFUSE_JELLYFIN_TOKEN="$TOKEN2" \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test2 --jellyfin-pass test2 \
  --jellyfin-name Jellyfin2 --jellyfin-scan --library-report "$OUT/restricted.json" \
  --quit-after 8 >"$OUT/restricted.log" 2>&1 || true
curl -sS -o /dev/null -X POST "http://127.0.0.1:8096/Users/$USER2/Policy" -H "$TH" \
  -H 'Content-Type: application/json' --data @"$OUT/allowed.json"
TOKEN2=$(login2)
OPENFUSE_SUPPORT_DIR="$OUT/allowed-support" \
OPENFUSE_JELLYFIN_PASSWORD=test2 OPENFUSE_JELLYFIN_TOKEN="$TOKEN2" \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test2 --jellyfin-pass test2 \
  --jellyfin-name Jellyfin2 --jellyfin-scan --library-report "$OUT/allowed.json" \
  --quit-after 8 >"$OUT/allowed.log" 2>&1 || true
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
restricted = json.load(open(os.path.join(out, "restricted.json")))
allowed = json.load(open(os.path.join(out, "allowed.json")))
if restricted.get("rawWorks") != 0:
    errors.append(f"restricted saw {restricted.get('rawWorks')} works")
if allowed.get("rawWorks", 0) < 2:
    errors.append(f"allowed saw {allowed.get('rawWorks')} works")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Jellyfin per-user library permissions enforced")
PY
