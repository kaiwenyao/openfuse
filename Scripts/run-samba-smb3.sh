#!/bin/bash
# M5ak: real Samba SMB3 share scan/play/seek.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/samba-smb3"
SHARE="$OUT/share"
rm -rf "$OUT"; mkdir -p "$SHARE/Movie" "$OUT/support"
cp Fixtures/generated/openfuse-fixture.mkv "$SHARE/Movie/OpenFuse Samba.mkv"
cp Fixtures/mobile/openfuse-mobile.zh-Hans.srt "$SHARE/Movie/OpenFuse Samba.zh-Hans.srt"
docker rm -f openfuse-samba >/dev/null 2>&1 || true
docker run -d --name openfuse-samba -p 1445:445 -v "$SHARE:/mount" \
  dperson/samba -p -u "test;test" -s "SHARE;/mount;yes;no;no;test" >/dev/null
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
  --quit-after 10 >"$OUT/play.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
library = json.load(open(os.path.join(out, "library.json")))
versions = library["items"][0]["episodes"][0]["versions"] if library.get("items") else []
if not versions:
    errors.append("no versions")
elif versions[0].get("resolution") != "1080p":
    errors.append(f"resolution {versions[0].get('resolution')}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 10:
    errors.append(f"position {play.get('position')}")
if not str(play.get("selectedSubtitle", "")).startswith("mpv:"):
    errors.append(f"subtitle {play.get('selectedSubtitle')}")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: real Samba SMB3 scan/play/seek/subtitle")
PY
