#!/bin/bash
# M4z: iPhone fetches progress over HTTPS with a CA copied into its container.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${OPENFUSE_IOS_SIM:-E3AEF363-7F63-4945-A5AF-097DFBD4CDC6}"
BUNDLE=com.openfuse.mobile
OUT="$PWD/build/ios-sync-https"
TLS="$OUT/tls"
ROOT="$PWD/build/real-jellyfin"
rm -rf "$OUT"; mkdir -p "$TLS"
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
cat > "$OUT/record.json" <<'JSON'
[{"mediaPath":"jellyfin://c135dd80bab7e30f/c9a8049da54e0f1e4ffbf6cce67cee71/c9a8049da54e0f1e4ffbf6cce67cee71","fileSize":0,"duration":20.082,"position":11.0,"lastPlayedAt":"2026-11-20T11:55:00.000Z","isFinished":false,"playCount":0,"displayTitle":"OpenFuse Jellyfin","sourceKind":"jellyfin","sourceID":"c135dd80bab7e30f"}]
JSON
curl -sS --cacert "$TLS/ca.pem" -H 'Authorization: Bearer sync-test' \
  -H 'Content-Type: application/json' -X POST https://127.0.0.1:8131/progress \
  --data-binary @"$OUT/record.json" >/dev/null
Scripts/build-ios.sh "platform=iOS Simulator,id=$SIM" "$OUT/build" Debug >/dev/null
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$OUT/build/Build/Products/Debug-iphonesimulator/OpenFuse.app"
DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
mkdir -p "$DATA/Documents"
cp "$TLS/ca.pem" "$DATA/Documents/ca.pem"
SIMCTL_CHILD_OPENFUSE_AUTOPLAY=1 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_SOURCE=jellyfin \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_TITLE='OpenFuse Jellyfin' \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_PAUSE_AT=13 \
SIMCTL_CHILD_OPENFUSE_AUTOPLAY_STOP_AFTER=18 \
SIMCTL_CHILD_OPENFUSE_REPORT_RESUME=1 \
SIMCTL_CHILD_OPENFUSE_SYNC_URL=https://127.0.0.1:8131/progress \
SIMCTL_CHILD_OPENFUSE_SYNC_TOKEN=sync-test \
SIMCTL_CHILD_OPENFUSE_SYNC_CA="$DATA/Documents/ca.pem" \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_URL=http://127.0.0.1:8096 \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_USER=test \
SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_PASSWORD=test \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/ios.log" 2>&1 &
sleep 9
xcrun simctl io "$SIM" screenshot "$OUT/play.png" >/dev/null 2>&1 || true
sleep 6
cp "$DATA/Library/Application Support/OpenFuse/autoplay-resume.json" "$OUT/resume.json" 2>/dev/null || true
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
resume = json.load(open(os.path.join(out, "resume.json")))
if resume.get("resume", 0) < 10:
    errors.append(f"resume {resume}")
log = open(os.path.join(out, "sync.log"), encoding="utf-8", errors="replace").read()
if '"method": "GET"' not in log or '"method": "POST"' not in log:
    errors.append("HTTPS GET/POST missing")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: iPhone HTTPS CA sync resume {resume['resume']:.2f}s")
PY
