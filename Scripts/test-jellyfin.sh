#!/bin/bash
# Protocol-level Jellyfin checks against the local fixture.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${JELLYFIN_TEST_PORT:-8106}"
LOG="build/jellyfin-test.log"
PROBE=".build/debug/openfuse-probe"

if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
swift build --product openfuse-probe >/dev/null

python3 Tools/jellyfin_fixture.py --setup --port "$PORT" >"$LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for _ in {1..30}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$PORT/System/Info/Public" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

export OPENFUSE_JELLYFIN_USER=test
export OPENFUSE_JELLYFIN_PASSWORD=test
"$PROBE" jellyfin "http://127.0.0.1:$PORT" > build/jellyfin-probe.json
python3 - <<'PY'
import json
report = json.load(open("build/jellyfin-probe.json"))
assert report["userID"] == "user-1", report
assert [v["name"] for v in report["views"]] == ["电影", "电视剧"], report
assert report["items"] and report["items"][0]["id"] == "movie-1", report
assert len(report["versions"]) == 2, report
assert report["streamURL"].startswith("http://127.0.0.1:"), report
assert "TOKEN" in report["imageURL"], report
print("PASS: login, views, items, 2 versions, absolute stream URL")
PY

curl -sS --max-time 5 -r 0-1023 -H "X-Emby-Token: jf-test-token" \
  "http://127.0.0.1:$PORT/Videos/ep-1/stream?Static=true&MediaSourceId=ms-ep-1-1080" \
  -o build/jellyfin-range.bin
python3 - <<'PY'
data = open("build/jellyfin-range.bin", "rb").read()
assert len(data) == 1024, len(data)
assert data[:4].hex() == "1a45dfa3", data[:4].hex()
print("PASS: authenticated Range stream, MKV magic")
PY

if OPENFUSE_JELLYFIN_PASSWORD=wrong "$PROBE" jellyfin "http://127.0.0.1:$PORT" >/dev/null 2>&1; then
  echo "FAIL: wrong password accepted" >&2
  exit 1
fi
echo "PASS: wrong password rejected"
