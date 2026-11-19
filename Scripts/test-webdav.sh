#!/bin/bash
# Protocol-level WebDAV checks against the local fixture server.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${WEBDAV_TEST_PORT:-8101}"
LOG="build/webdav-test.log"
PROBE=".build/debug/openfuse-probe"

if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then
  Scripts/make_fixtures.sh
fi
swift build --product openfuse-probe >/dev/null

python3 Tools/webdav_fixture.py --setup --port "$PORT" >"$LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for _ in {1..30}; do
  if curl -sS --max-time 1 -u test:test -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

BASE="http://127.0.0.1:$PORT/dav/"
export OPENFUSE_WEBDAV_USER=test
export OPENFUSE_WEBDAV_PASSWORD=test

"$PROBE" webdav "$BASE" "Movies/OpenFuse Fixture (2026)" > build/webdav-probe.json
python3 - <<'PY'
import json
report = json.load(open("build/webdav-probe.json"))
entries = report["entries"]
video = next(e for e in entries if e["name"] == "OpenFuse Fixture.mkv")
subs = [e["name"] for e in entries if e["name"].endswith(".ass")]
assert video["size"] > 10_000_000, video
assert set(subs) == {
    "OpenFuse Fixture.ass", "OpenFuse Fixture.zh-Hans.ass", "OpenFuse Fixture.zh-Hant.ass"
}, subs
assert report["rangeStatus"] == 206, report
assert report["magic"] == "1a45dfa3", report
assert report["rangeContentRange"].startswith("bytes 0-1023/"), report
print("PASS: PROPFIND, Unicode path, 3 sidecars, Range 206, MKV magic")
PY

"$PROBE" webdav "$BASE" "Movies/100% 测试" > build/webdav-unicode.json
python3 - <<'PY'
import json
report = json.load(open("build/webdav-unicode.json"))
names = [e["name"] for e in report["entries"]]
assert "说明.txt" in names, names
print("PASS: percent-encoded Unicode directory", names)
PY

if OPENFUSE_WEBDAV_PASSWORD=wrong "$PROBE" webdav "$BASE" "" >/dev/null 2>&1; then
  echo "FAIL: wrong password was accepted" >&2
  exit 1
fi
echo "PASS: Basic auth rejects a wrong password"
