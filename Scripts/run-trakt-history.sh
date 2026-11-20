#!/bin/bash
# M4s: import Trakt movie/show history and verify watched filter.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/trakt-history"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/trakt_fixture.py --port 8123 --log "$OUT/trakt.log" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 http://127.0.0.1:8123/sync/history/movies >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --scan-local build/library-fixture \
  --library-report "$OUT/library.json" --quit-after 3 >"$OUT/scan.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_TRAKT_BASE_URL=http://127.0.0.1:8123 \
OPENFUSE_TRAKT_CLIENT_ID=test-client \
OPENFUSE_TRAKT_TOKEN=trakt-test-token \
"$APP" --sync-trakt --quit-after 5 >"$OUT/sync.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --library-watch watched \
  --library-report "$OUT/watched.json" --capture-ui "$OUT/watched.png" \
  --ui-after 5 --quit-after 7 >"$OUT/watched.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
log = open(os.path.join(out, "trakt.log"), encoding="utf-8").read()
for needle in ["/sync/history/movies", "/sync/history/shows"]:
    if needle not in log:
        errors.append(f"missing {needle}")
log_text = open(os.path.join(out, "sync.log"), encoding="utf-8").read()
if "匹配 3 集" not in log_text:
    errors.append(f"sync count: {log_text.strip()}")
watched = json.load(open(os.path.join(out, "watched.json")))
for title in ["OpenFuse Fixture", "示例剧"]:
    if title not in watched.get("visible", []):
        errors.append(f"missing watched {title}")
if not os.path.exists(os.path.join(out, "watched.png")):
    errors.append("watched screenshot missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Trakt history matched 3 episodes; watched filter has movie+show")
PY
