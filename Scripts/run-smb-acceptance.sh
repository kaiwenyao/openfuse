#!/bin/bash
# M5l SMB: add/scan share, cache a video, play through libmpv.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/smb-acceptance"
SHARE_DIR="$OUT/share"
PORT=1445
if [[ ! -f /opt/homebrew/lib/libsmb2.dylib ]]; then
  echo "missing libsmb2: build/install from https://github.com/sahlberg/libsmb2" >&2
  exit 1
fi
if [[ ! -x build/impacket-venv/bin/python ]]; then
  python3 -m venv build/impacket-venv
  build/impacket-venv/bin/pip install impacket >/dev/null
fi
rm -rf "$OUT"; mkdir -p "$SHARE_DIR/Movie"
cp Fixtures/generated/openfuse-fixture.mkv "$SHARE_DIR/Movie/OpenFuse.SMB.mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
build/impacket-venv/bin/smbserver.py -port "$PORT" -username test -password test -smb2support \
  SHARE "$SHARE_DIR" >"$OUT/server.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..60}; do
  if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test "$APP" \
  --smb-server 127.0.0.1 --smb-port "$PORT" --smb-share SHARE --smb-user test --smb-pass test \
  --smb-name SMB --smb-scan --library-report "$OUT/library.json" \
  --capture-ui "$OUT/library.png" --ui-after 8 --quit-after 10 >"$OUT/app.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
print(data["items"][0]["episodes"][0]["id"])
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test "$APP" \
  --library-play "$EPISODE" --freeze-at 9.9 --capture "$OUT/play.png" \
  --capture-after 16 --report "$OUT/play.json" --quit-after 18 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
library = json.load(open(os.path.join(out, "library.json")))
if library["rawWorks"] != 1 or library["rawEpisodes"] != 1:
    errors.append(f"counts {library['rawWorks']}/{library['rawEpisodes']}")
if library["items"][0]["sourceKind"] != "smb":
    errors.append("sourceKind not smb")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("sourceKind") != "smb" or not 9.8 <= play.get("position", 0) <= 10.1:
    errors.append(f"play {play.get('sourceKind')} {play.get('position')}")
if "OpenFuse.SMB.mkv" not in play.get("remotePath", ""):
    errors.append(f"remotePath {play.get('remotePath')}")
for name in ["library.png", "play.png"]:
    if not os.path.exists(os.path.join(out, name)):
        errors.append(f"missing {name}")
cache = os.path.join(out, "support", "SMBCache")
if not os.path.isdir(cache) or not os.listdir(cache):
    errors.append("SMBCache empty")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: SMB scan 1 work/1 episode, sourceKind=smb, cached playback 9.9s")
PY
