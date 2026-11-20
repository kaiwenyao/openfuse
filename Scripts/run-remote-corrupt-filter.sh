#!/bin/bash
# M3s: WebDAV/SMB signature filtering rejects corrupt files.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/remote-corrupt-filter"
rm -rf "$OUT"; mkdir -p "$OUT/webdav/Movie" "$OUT/smb/Movie" "$OUT/support-webdav" "$OUT/support-smb"
cp Fixtures/mobile/openfuse-mobile.mp4 "$OUT/webdav/Movie/Good.Movie.mp4"
cp Fixtures/mobile/openfuse-mobile.mp4 "$OUT/smb/Movie/Good.Movie.mp4"
printf 'not a video' > "$OUT/webdav/Movie/Broken.Movie.mkv"
printf 'not a video' > "$OUT/smb/Movie/Broken.Movie.mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/webdav_fixture.py --root "$OUT/webdav" --port 8122 --log "$OUT/webdav.log" >"$OUT/webdav.out" 2>&1 &
WPID=$!
build/impacket-venv/bin/smbserver.py -port 1445 -username test -password test -smb2support \
  SHARE "$OUT/smb" >"$OUT/smb.log" 2>&1 &
SPID=$!
trap 'kill "$WPID" "$SPID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test http://127.0.0.1:8122/dav/ >/dev/null 2>&1 \
     && nc -z 127.0.0.1 1445 >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support-webdav" \
OPENFUSE_WEBDAV_USER=test OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url http://127.0.0.1:8122/dav/ --webdav-user test --webdav-pass test \
  --webdav-name WebDAV --webdav-scan --library-report "$OUT/webdav.json" --quit-after 8 \
  >"$OUT/webdav-app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support-smb" OPENFUSE_SMB_PASSWORD=test \
  "$APP" --smb-server 127.0.0.1 --smb-port 1445 --smb-share SHARE --smb-user test \
  --smb-pass test --smb-name SMB --smb-scan --library-report "$OUT/smb.json" --quit-after 8 \
  >"$OUT/smb-app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
for name in ("webdav", "smb"):
    data = json.load(open(os.path.join(out, f"{name}.json")))
    titles = [item["title"] for item in data.get("items", [])]
    if "Broken Movie" in titles:
        errors.append(f"{name}: corrupt file in library {titles}")
    if "Good Movie" not in titles:
        errors.append(f"{name}: valid file missing {titles}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: WebDAV+SMB corrupt files filtered, valid files kept")
PY
