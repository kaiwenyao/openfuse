#!/bin/bash
# M5ar: 32 concurrent Range clients during SMB playback.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/samba-concurrency-32"
SHARE="$OUT/share"
SAMPLE="$PWD/build/samba-2gb/OpenFuse.2GB.mkv"
rm -rf "$OUT"; mkdir -p "$SHARE" "$OUT/support" "$OUT/ranges"
if [[ ! -f "$SAMPLE" ]]; then
  echo "run Scripts/run-samba-2gb.sh first" >&2
  exit 2
fi
cp "$SAMPLE" "$SHARE/OpenFuse.Concurrency32.mkv"
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
pkill -f "OpenFuse.app/Contents/MacOS/OpenFuse" 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test \
  "$APP" --smb-server 127.0.0.1 --smb-port 1445 --smb-share SHARE --smb-user test \
  --smb-pass test --smb-name Samba --smb-scan --library-report "$OUT/library.json" \
  --quit-after 12 >"$OUT/scan.log" 2>&1 || true
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
print(data["items"][0]["episodes"][0]["id"])
PY
)
rm -f "$OUT/play.json"
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test \
  "$APP" --library-play "$EPISODE" --seek 1200 --freeze-at 1202 \
  --capture "$OUT/play.png" --capture-after 8 --report "$OUT/play.json" \
  --quit-after 45 >"$OUT/play.log" 2>&1 &
APPPID=$!
for _ in {1..20}; do
  [[ -f "$OUT/play.json" ]] && break
  sleep 1
done
PORT=$(python3 - "$OUT" <<'PY'
import json, sys, urllib.parse
data = json.load(open(f"{sys.argv[1]}/play.json"))
print(urllib.parse.urlparse(data["file"]).port)
PY
)
RSS_BEFORE=$(ps -o rss= -p "$APPPID" | awk '{print $1/1024}')
PIDS=()
for i in {0..31}; do
  START=$((i * 50000000))
  END=$((START + 1048575))
  curl -sS --max-time 30 -o "$OUT/ranges/$i.bin" -w "%{http_code} %{size_download}\n" \
    -H "Range: bytes=$START-$END" "http://127.0.0.1:$PORT/stream" \
    > "$OUT/ranges/$i.txt" &
  PIDS+=($!)
done
wait "${PIDS[@]}"
RSS_AFTER=$(ps -o rss= -p "$APPPID" | awk '{print $1/1024}')
wait "$APPPID" 2>/dev/null || true
RSS_BEFORE="$RSS_BEFORE" RSS_AFTER="$RSS_AFTER" python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
for index in range(32):
    line = open(os.path.join(out, "ranges", f"{index}.txt")).read().strip()
    if line != "206 1048576":
        errors.append(f"range {index}: {line}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 1200:
    errors.append(f"position {play.get('position')}")
before = float(os.environ["RSS_BEFORE"])
after = float(os.environ["RSS_AFTER"])
if after > before + 200:
    errors.append(f"RSS grew {before}->{after} MB")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: 32 concurrent ranges, playback continued, RSS {before:.0f}->{after:.0f}MB")
PY
