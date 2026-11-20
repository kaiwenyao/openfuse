#!/bin/bash
# M5af: SMB MP4 atom parser yields resolution.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/smb-mp4"
rm -rf "$OUT"; mkdir -p "$OUT/share/Movie" "$OUT/support"
cp Fixtures/mobile/openfuse-mobile.mp4 "$OUT/share/Movie/OpenFuse.Mobile.mp4"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
build/impacket-venv/bin/smbserver.py -port 1445 -username test -password test -smb2support \
  SHARE "$OUT/share" >"$OUT/server.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if nc -z 127.0.0.1 1445 >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_SMB_PASSWORD=test \
  "$APP" --smb-server 127.0.0.1 --smb-port 1445 --smb-share SHARE --smb-user test \
  --smb-pass test --smb-name SMB --smb-scan --library-report "$OUT/library.json" \
  --quit-after 8 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
data = json.load(open(os.path.join(out, "library.json")))
versions = data["items"][0]["episodes"][0]["versions"] if data.get("items") else []
if not versions:
    errors.append("no versions")
else:
    if versions[0].get("resolution") != "1080p":
        errors.append(f"resolution {versions[0].get('resolution')}")
    if not versions[0].get("contentKey"):
        errors.append("contentKey missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: SMB MP4 atom parser yields 1080p")
PY
