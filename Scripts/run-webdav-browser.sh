#!/bin/bash
# WebDAV browser navigation acceptance, without Docker.
#
#   Scripts/run-webdav-browser.sh
#
# Starts Scripts/webdav_fixture.py (PROPFIND + ranged GET) over a two-level
# tree, opens the browser deep in that tree and screenshots the breadcrumb.
# The server log is the functional assertion: the deep directory must be listed
# exactly once, and no concatenated path may appear. The old append bug sent
# requests such as `/dav/Shows/Season%201/Shows/Season%201/` and repeated the
# breadcrumb segments. The click-while-loading race itself is covered by
# Tests/OpenFuseCoreTests/RemotePathTests.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/webdav-browser"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
ROOT="$OUT/dav-root"

rm -rf "$OUT"
mkdir -p "$ROOT/Shows/Season 1" "$OUT/support"
cp Fixtures/generated/video.mkv "$ROOT/Shows/Season 1/episode.mkv"
printf 'notes\n' > "$ROOT/Shows/readme.txt"

Scripts/build-app.sh >/dev/null
swift test --filter RemotePathTests >/dev/null

python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" >"$OUT/server.log" 2>&1 &
SERVER_PID=$!
# Fail fast if the fixture could not bind.
sleep 0.5
if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
  echo "FAIL: WebDAV fixture did not start:"
  cat "$OUT/server.log"
  exit 1
fi
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT

for _ in {1..40}; do
  if curl -sS --max-time 1 -X PROPFIND -H 'Depth: 0' \
      "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Fixture \
  --webdav-user admin --webdav-pass test \
  --webdav-browse --webdav-browse-path "Shows/Season 1" \
  --capture-ui "$OUT/breadcrumb.png" --ui-after 4 --quit-after 6 \
  >"$OUT/app.log" 2>&1 || true

if [[ ! -s "$OUT/breadcrumb.png" ]]; then
  echo "FAIL: no browser screenshot"
  exit 1
fi
if grep -q "失败\|无法读取\|无法连接" "$OUT/app.log"; then
  echo "FAIL: browser reported an error:"
  grep -q "失败\|无法读取\|无法连接" "$OUT/app.log" | head -5
  exit 1
fi

python3 "$PWD/Scripts/webdav_browse_assert.py" "$OUT/server.log"
echo "captures: $OUT"
