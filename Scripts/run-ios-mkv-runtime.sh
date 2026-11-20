#!/bin/bash
# M3r: iOS runtime WebDAV MKV scan uses the pure-Swift header parser.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${OPENFUSE_IOS_SIM:-E3AEF363-7F63-4945-A5AF-097DFBD4CDC6}"
BUNDLE=com.openfuse.mobile
OUT="$PWD/build/ios-mkv-runtime"
rm -rf "$OUT"; mkdir -p "$OUT/webdav/Movie"
cp Fixtures/generated/openfuse-hdr.mkv "$OUT/webdav/Movie/OpenFuse.HDR.mkv"
python3 Tools/webdav_fixture.py --root "$OUT/webdav" --port 8122 --log "$OUT/webdav.log" >"$OUT/webdav.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
Scripts/build-ios.sh "platform=iOS Simulator,id=$SIM" "$OUT/build" Debug >/dev/null
APP="$OUT/build/Build/Products/Debug-iphonesimulator/OpenFuse.app"
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
SIMCTL_CHILD_OPENFUSE_TEST_WEBDAV_URL=http://127.0.0.1:8122/dav/ \
SIMCTL_CHILD_OPENFUSE_TEST_WEBDAV_USER=test \
SIMCTL_CHILD_OPENFUSE_TEST_WEBDAV_PASSWORD=test \
  xcrun simctl launch --console "$SIM" "$BUNDLE" >"$OUT/launch.log" 2>&1 &
sleep 10
xcrun simctl io "$SIM" screenshot "$OUT/library.png" >/dev/null 2>&1 || true
DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
DB="$DATA/Library/Application Support/OpenFuse/library.sqlite"
python3 - "$DB" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
rows = db.execute("select name,resolution,dynamic_range from versions").fetchall()
errors = []
print(rows)
if not any(resolution == "1080p" and dynamic == "HDR10" for _, resolution, dynamic in rows):
    errors.append(f"no WebDAV 1080p/HDR10 version: {rows}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: iOS runtime parsed WebDAV MKV as 1080p/HDR10")
PY
