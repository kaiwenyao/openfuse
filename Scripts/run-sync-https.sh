#!/bin/bash
# M4y: HTTPS progress sync pinned to a local CA.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/sync-https"
TLS="$OUT/tls"
ROOT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$TLS" "$OUT/support"
if [[ ! -f "$ROOT/config/config/system.xml" ]]; then
  echo "run Scripts/run-real-jellyfin.sh first" >&2
  exit 2
fi
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TLS/ca.key" -out "$TLS/ca.pem" \
  -days 2 -subj '/CN=OpenFuse Test CA' >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$TLS/server.key" -out "$TLS/server.csr" \
  -subj '/CN=127.0.0.1' >/dev/null 2>&1
printf 'subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth\n' > "$TLS/san.cnf"
openssl x509 -req -in "$TLS/server.csr" -CA "$TLS/ca.pem" -CAkey "$TLS/ca.key" \
  -CAcreateserial -out "$TLS/server.pem" -days 2 -extfile "$TLS/san.cnf" >/dev/null 2>&1
lsof -ti tcp:8131 | xargs -r kill 2>/dev/null || true
python3 Tools/progress_sync_fixture.py --port 8131 --token sync-test \
  --tls-cert "$TLS/server.pem" --tls-key "$TLS/server.key" --log "$OUT/sync.log" \
  >"$OUT/sync.out" 2>&1 &
SYNCPID=$!
docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true
docker run -d --name openfuse-jellyfin -p 8096:8096 \
  -v "$ROOT/config:/config" -v "$ROOT/cache:/cache" -v "$ROOT/media:/media" \
  jellyfin/jellyfin:latest >/dev/null
trap 'kill $SYNCPID >/dev/null 2>&1 || true; docker rm -f openfuse-jellyfin >/dev/null 2>&1 || true' EXIT
for _ in {1..60}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public 2>/dev/null | grep -q '"Id"'; then break; fi
  sleep 1
done
sleep 1
H='Authorization: MediaBrowser Client="OpenFuse", Device="Mac", DeviceId="admin", Version="1.0"'
TOKEN=$(curl -sS -X POST http://127.0.0.1:8096/Users/AuthenticateByName -H "$H" \
  -H 'Content-Type: application/json' -d '{"Username":"test","Pw":"test"}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessToken"])')
Scripts/build-app.sh >/dev/null
swift test >/dev/null
pkill -f "OpenFuse.app/Contents/MacOS/OpenFuse" 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_PASSWORD=test OPENFUSE_JELLYFIN_TOKEN="$TOKEN" \
  "$APP" --jellyfin-url http://127.0.0.1:8096 --jellyfin-user test --jellyfin-pass test \
  --jellyfin-name Jellyfin --jellyfin-scan --library-report "$OUT/library.json" \
  --quit-after 8 >"$OUT/scan.log" 2>&1 || true
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_JELLYFIN_TOKEN="$TOKEN" OPENFUSE_SYNC_URL=https://127.0.0.1:8131/progress \
OPENFUSE_SYNC_TOKEN=sync-test OPENFUSE_SYNC_CA="$TLS/ca.pem" \
  "$APP" --sync-progress --quit-after 6 >"$OUT/sync-app.log" 2>&1 || true
CURL_OK=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$TLS/ca.pem" \
  -H 'Authorization: Bearer sync-test' https://127.0.0.1:8131/progress || true)
if curl -sS --max-time 3 -o /dev/null -H 'Authorization: Bearer sync-test' \
  https://127.0.0.1:8131/progress >/dev/null 2>&1; then
  CURL_NO_CA=0
else
  CURL_NO_CA=1
fi
CURL_OK="$CURL_OK" CURL_NO_CA="$CURL_NO_CA" python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
status = os.environ.get("CURL_OK")
if status != "200":
    errors.append(f"curl with CA {status}")
if os.environ.get("CURL_NO_CA") != "1":
    errors.append("curl without CA unexpectedly succeeded")
log = open(os.path.join(out, "sync.log"), encoding="utf-8", errors="replace").read()
if '"method": "POST"' not in log:
    errors.append("no HTTPS POST")
if "同步完成" not in open(os.path.join(out, "sync-app.log"), encoding="utf-8", errors="replace").read():
    errors.append("app HTTPS sync did not complete")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: HTTPS sync with pinned CA, unpinned rejected")
PY
