#!/bin/bash
# M5am: large SMB file streams/seeks without whole-file caching.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/samba-large-acceptance"
SHARE="$OUT/share"
SAMPLE="$PWD/build/samba-large/OpenFuse.Large.mkv"
rm -rf "$OUT"; mkdir -p "$SHARE/Movie" "$OUT/support"
if [[ ! -f "$SAMPLE" ]]; then
  mkdir -p "$(dirname "$SAMPLE")"
  /opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i testsrc2=size=1920x1080:rate=24 \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 120 \
    -c:v libx265 -pix_fmt yuv420p10le -b:v 6000k -x265-params log-level=error \
    -c:a eac3 -b:a 256k -ac 6 -shortest "$SAMPLE"
fi
cp "$SAMPLE" "$SHARE/Movie/OpenFuse.Large.mkv"
cp Fixtures/mobile/openfuse-mobile.zh-Hans.srt "$SHARE/Movie/OpenFuse.Large.zh-Hans.srt"
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
  "$APP" --library-play "$EPISODE" --seek 60 --freeze-at 62 \
  --capture "$OUT/play.png" --capture-after 10 --report "$OUT/play.json" --quit-after 14 \
  >"$OUT/play.log" 2>&1 &
APPPID=$!
sleep 8
RSS=$(ps -o rss= -p "$APPPID" | awk '{print $1/1024}')
wait "$APPPID" || true
python3 - "$OUT" "$RSS" <<'PY'
import json, os, sys
out, rss = sys.argv[1], float(sys.argv[2])
errors = []
data = json.load(open(os.path.join(out, "library.json")))
versions = data["items"][0]["episodes"][0]["versions"] if data.get("items") else []
if not versions or versions[0].get("resolution") != "1080p":
    errors.append(f"versions {versions}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("duration", 0) < 119:
    errors.append(f"duration {play.get('duration')}")
if play.get("position", 0) < 60:
    errors.append(f"position {play.get('position')}")
if play.get("sourceKind") != "smb" or "127.0.0.1" not in play.get("file", ""):
    errors.append(f"file {play.get('file')}")
if rss > 500:
    errors.append(f"RSS {rss} MB suggests buffering")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: 120s/90MB SMB stream seek 62s, RSS {rss:.0f}MB")
PY
