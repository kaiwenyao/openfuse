#!/bin/bash
# M5u: concurrent SMB Range requests return correct bytes.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/smb-range-concurrency"
SHARE="$OUT/share"
rm -rf "$OUT"; mkdir -p "$SHARE/Movie"
cp Fixtures/generated/openfuse-fixture.mkv "$SHARE/Movie/OpenFuse.SMB.mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
if [[ ! -x build/impacket-venv/bin/python ]]; then
  python3 -m venv build/impacket-venv
  build/impacket-venv/bin/pip install impacket >/dev/null
fi
build/impacket-venv/bin/smbserver.py -port 1445 -username test -password test -smb2support \
  SHARE "$SHARE" >"$OUT/server.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if nc -z 127.0.0.1 1445 >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test "$APP" \
  --smb-server 127.0.0.1 --smb-port 1445 --smb-share SHARE --smb-user test --smb-pass test \
  --smb-name SMB --smb-scan --library-report "$OUT/library.json" --quit-after 8 \
  >"$OUT/scan.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
print(data["items"][0]["episodes"][0]["id"])
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test "$APP" \
  --library-play "$EPISODE" --report "$OUT/play.json" --capture-after 5 \
  --quit-after 25 >"$OUT/play.log" 2>&1 &
APPPID=$!
sleep 8
URL=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/play.json"))
print(data["file"])
PY
)
curl -s -r 0-1048575 "$URL" -o "$OUT/a.bin" &
P1=$!
curl -s -r 10000000-11048575 "$URL" -o "$OUT/b.bin" &
P2=$!
wait "$P1" "$P2"
kill "$APPPID" 2>/dev/null || true
dd if=Fixtures/generated/openfuse-fixture.mkv of="$OUT/ra.bin" bs=1 skip=0 count=1048576 2>/dev/null
dd if=Fixtures/generated/openfuse-fixture.mkv of="$OUT/rb.bin" bs=1 skip=10000000 count=1048576 2>/dev/null
A=$(shasum -a 256 "$OUT/a.bin" | awk '{print $1}')
B=$(shasum -a 256 "$OUT/b.bin" | awk '{print $1}')
RA=$(shasum -a 256 "$OUT/ra.bin" | awk '{print $1}')
RB=$(shasum -a 256 "$OUT/rb.bin" | awk '{print $1}')
if [[ "$A" != "$RA" || "$B" != "$RB" ]]; then
  echo "FAIL: hashes differ A=$A/$RA B=$B/$RB" >&2
  exit 1
fi
echo "PASS: concurrent SMB Range 0..1MB and 10MB..+1MB match fixture"
