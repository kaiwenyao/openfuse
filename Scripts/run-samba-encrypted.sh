#!/bin/bash
# M5al: Samba SMB3 mandatory signing + required encryption.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/samba-encrypted"
SHARE="$OUT/share"
rm -rf "$OUT"; mkdir -p "$SHARE/Movie" "$OUT/support"
cp Fixtures/generated/openfuse-fixture.mkv "$SHARE/Movie/OpenFuse Samba.mkv"
cp Fixtures/mobile/openfuse-mobile.zh-Hans.srt "$SHARE/Movie/OpenFuse Samba.zh-Hans.srt"
docker rm -f openfuse-samba >/dev/null 2>&1 || true
docker run -d --name openfuse-samba -p 1445:445 -v "$SHARE:/mount" dperson/samba -p \
  -g "server signing = mandatory" -g "smb encrypt = required" -g "server min protocol = SMB3" \
  -u "test;test" -s "SHARE;/mount;yes;no;no;test" >/dev/null
trap 'docker rm -f openfuse-samba >/dev/null 2>&1 || true' EXIT
for _ in {1..40}; do
  if nc -z 127.0.0.1 1445 >/dev/null 2>&1; then break; fi
  sleep 0.25
done
sleep 2
Scripts/build-app.sh >/dev/null
swift test >/dev/null
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_SMB_PASSWORD=test \
  "$APP" --smb-server 127.0.0.1 --smb-port 1445 --smb-share SHARE --smb-user test \
  --smb-pass test --smb-name Samba --smb-scan --library-report "$OUT/library.json" \
  --quit-after 8 >"$OUT/scan.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
print(data["items"][0]["episodes"][0]["id"])
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_SMB_PASSWORD=test \
  "$APP" --library-play "$EPISODE" --seek 10 --freeze-at 11 \
  --capture "$OUT/play.png" --capture-after 8 --report "$OUT/play.json" \
  --quit-after 15 >"$OUT/play.log" 2>&1 &
APPPID=$!
sleep 6
docker exec openfuse-samba smbstatus -b >"$OUT/smbstatus.txt" 2>&1 || true
wait "$APPPID" || true
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 10:
    errors.append(f"position {play.get('position')}")
status = open(os.path.join(out, "smbstatus.txt"), encoding="utf-8", errors="replace").read()
if "SMB3_11" not in status:
    errors.append("not SMB3_11")
if "AES-128-CCM" not in status:
    errors.append("no AES-128-CCM encryption")
if "AES-128-CMAC" not in status:
    errors.append("no AES-128-CMAC signing")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Samba SMB3_11 signed+encrypted playback")
PY
