#!/bin/bash
# M5at: 3-minute playback soak with periodic 8-way Range bursts.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/samba-soak"
SHARE="$OUT/share"
SAMPLE="$PWD/build/samba-2gb/OpenFuse.2GB.mkv"
ROUNDS="${OPENFUSE_SOAK_ROUNDS:-12}"
rm -rf "$OUT"; mkdir -p "$SHARE" "$OUT/support" "$OUT/ranges"
if [[ ! -f "$SAMPLE" ]]; then
  echo "run Scripts/run-samba-2gb.sh first" >&2
  exit 2
fi
cp "$SAMPLE" "$SHARE/OpenFuse.Soak.mkv"
docker rm -f openfuse-samba >/dev/null 2>&1 || true
docker run -d --name openfuse-samba -p 1445:445 -v "$SHARE:/mount" \
  dperson/samba -p -u "test;test" -s "SHARE;/mount;yes;no;no;test" >/dev/null
trap 'docker rm -f openfuse-samba >/dev/null 2>&1 || true' EXIT
for _ in {1..40}; do
  nc -z 127.0.0.1 1445 >/dev/null 2>&1 && break
  sleep 0.25
done
sleep 2
Scripts/build-app.sh >/dev/null
swift test >/dev/null
pkill -x OpenFuse 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_SMB_PASSWORD=test \
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
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_SMB_PASSWORD=test \
  "$APP" --library-play "$EPISODE" --seek 600 --capture "$OUT/play.png" \
  --capture-after 8 --report "$OUT/play.json" --quit-after 210 >"$OUT/play.log" 2>&1 &
APPPID=$!
for _ in {1..20}; do
  [[ -f "$OUT/play.json" ]] && break
  sleep 1
done
PORT=$(python3 - "$OUT" <<'PY'
import json, sys, urllib.parse
print(urllib.parse.urlparse(json.load(open(f"{sys.argv[1]}/play.json"))["file"]).port)
PY
)
RSS_START=$(ps -o rss= -p "$APPPID" | awk '{print $1/1024}')
N=0
for _ in $(seq 1 "$ROUNDS"); do
  PIDS=()
  for _ in {0..7}; do
    START=$((N * 20000000))
    END=$((START + 524287))
    curl -sS --max-time 30 -o "$OUT/ranges/$N.bin" -w "%{http_code} %{size_download}\n" \
      -H "Range: bytes=$START-$END" "http://127.0.0.1:$PORT/stream" \
      > "$OUT/ranges/$N.txt" &
    PIDS+=($!)
    N=$((N + 1))
  done
  wait "${PIDS[@]}"
  sleep 10
done
RSS_END=$(ps -o rss= -p "$APPPID" | awk '{print $1/1024}')
wait "$APPPID" 2>/dev/null || true
TOTAL=$((ROUNDS * 8))
RSS_START="$RSS_START" RSS_END="$RSS_END" python3 - "$OUT" "$TOTAL" <<'PY'
import json, os, sys
out = sys.argv[1]
total = int(sys.argv[2])
errors = []
for index in range(total):
    line = open(os.path.join(out, "ranges", f"{index}.txt")).read().strip()
    if line != "206 524288":
        errors.append(f"range {index}: {line}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 600:
    errors.append(f"position {play.get('position')}")
start = float(os.environ["RSS_START"])
end = float(os.environ["RSS_END"])
if end > start + 200:
    errors.append(f"RSS grew {start}->{end} MB")
if not os.path.exists(os.path.join(out, "play.png")):
    errors.append("screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: {total} ranges over {total//8*10}s, RSS {start:.0f}->{end:.0f}MB")
PY
