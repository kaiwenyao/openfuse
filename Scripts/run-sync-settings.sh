#!/bin/bash
# M6f: persist sync URL/CA, run sync from Settings, capture the panel.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/sync-settings"
TLS="$OUT/tls"
rm -rf "$OUT"; mkdir -p "$TLS" "$OUT/support"
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
trap 'kill $SYNCPID >/dev/null 2>&1 || true; defaults delete com.openfuse.app openfuse.sync.url >/dev/null 2>&1 || true; defaults delete com.openfuse.app openfuse.sync.ca >/dev/null 2>&1 || true' EXIT
sleep 1
defaults write com.openfuse.app openfuse.sync.url 'https://127.0.0.1:8131/progress'
defaults write com.openfuse.app openfuse.sync.ca "$TLS/ca.pem"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
pkill -x OpenFuse 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_JELLYFIN_TOKEN=test \
OPENFUSE_SYNC_TOKEN=sync-test "$APP" --sync-progress --quit-after 6 \
  >"$OUT/sync-app.log" 2>&1 || true
pkill -x OpenFuse 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_JELLYFIN_TOKEN=test \
  timeout 10 "$APP" --show-settings --capture-ui "$OUT/settings.png" --ui-after 2 --quit-after 5 \
  >"$OUT/settings.log" 2>&1 || true
python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
errors = []
log = open(os.path.join(out, "sync.log"), encoding="utf-8", errors="replace").read()
if '"method": "POST"' not in log:
    errors.append("settings-driven sync did not POST")
app = open(os.path.join(out, "sync-app.log"), encoding="utf-8", errors="replace").read()
if "同步完成" not in app:
    errors.append("sync did not complete")
if not os.path.exists(os.path.join(out, "settings.png")):
    errors.append("settings screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: persisted sync URL/CA drove HTTPS sync + Settings screenshot")
PY
