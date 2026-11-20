#!/bin/bash
# T07 recovery: one WebDAV directory times out; old works under it must survive.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/webdav-recovery"
ROOT="$OUT/root"
SUPPORT="$OUT/support"
PORT=8118
LOG="$OUT/server.log"
rm -rf "$OUT"; mkdir -p "$SUPPORT"
Scripts/build-app.sh >/dev/null
: > "$LOG"
python3 Tools/webdav_fixture.py --root "$ROOT" --setup --port "$PORT" --log "$LOG" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$SUPPORT" OPENFUSE_WEBDAV_PASSWORD=test "$APP" \
  --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-user test --webdav-name fixture \
  --webdav-scan --library-report "$OUT/base.json" --quit-after 3 >"$OUT/app.log" 2>&1 || true
sleep 0.5
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
python3 Tools/webdav_fixture.py --root "$ROOT" --port "$PORT" --fail-path "Shows/示例剧" --log "$LOG" >"$OUT/server.out" 2>&1 &
PID=$!
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$SUPPORT" OPENFUSE_WEBDAV_PASSWORD=test "$APP" \
  --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-user test --webdav-name fixture \
  --webdav-scan --library-report "$OUT/failed.json" --quit-after 3 >"$OUT/app.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
base = json.load(open(os.path.join(out, "base.json"), encoding="utf-8"))
failed = json.load(open(os.path.join(out, "failed.json"), encoding="utf-8"))
errors = []
if base["rawWorks"] != 2:
    errors.append(f"base works {base['rawWorks']}")
if failed["rawWorks"] != 2:
    errors.append(f"failed scan works {failed['rawWorks']} (old entries not preserved)")
if "保留旧条目" not in failed.get("status", ""):
    errors.append(f"status {failed.get('status')}")
titles = {item["title"] for item in failed["items"]}
if "示例剧 · WebDAV NFO" not in titles:
    errors.append(f"series missing: {titles}")
log = open(os.path.join(out, "server.log"), encoding="utf-8").read()
if '"status": 504' not in log:
    errors.append("fixture did not return 504")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: WebDAV 504 directory kept old works; other works rescanned")
print(f"reports: {out}")
PY
