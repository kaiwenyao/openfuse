#!/bin/bash
# Close-return-route acceptance for bug 1 of Docs/BUG-REVIEW-2026-11-27.md:
# closing the player from a «继续观看» resume used to land on the loading page
# instead of the page the user came from.
#
#   Scripts/run-close-return-route.sh
#
# What this script touches:
#   - launches build/OpenFuse.app only; every run gets its own
#     OPENFUSE_SUPPORT_DIR under build/close-return-route, so no personal data is
#     read or written and no `defaults` key is changed;
#   - no System Events / AppleScript and no synthetic mouse or keyboard input, so
#     no Accessibility permission is involved;
#   - screenshots come from AppModel.captureUI, which captures the app's own
#     window, so no Screen Recording permission is involved;
#   - Scripts/webdav_fixture.py listens on a free loopback port and is killed on
#     exit.
#
# The assertion is AppModel's `--route-log`: one JSON line per navigation state
# change. A screenshot alone cannot pin the moment the player closes, and the
# loading route can be visible for well under a frame budget.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/OpenFuse.app/Contents/MacOS/OpenFuse"
LOCAL="$PWD/Fixtures/mobile/openfuse-mobile.mp4"
OUT="$PWD/build/close-return-route"
rm -rf "$OUT"
mkdir -p "$OUT"

Scripts/build-app.sh >/dev/null
swift test --filter 'PlayerRoutePolicyTests|PlaybackClockTests' >/dev/null

FAIL=0
check() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL $3: expected $2, got $1"
    FAIL=1
  else
    echo "ok   $3: $1"
  fi
}

# Last recorded route / last recorded error of a route log.
route_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, field = sys.argv[1], sys.argv[2]
last = None
try:
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if line:
                last = json.loads(line)
except FileNotFoundError:
    pass
if last is None:
    print("<no-route-log>")
elif field == "loading":
    print("true" if last.get("loading") else "false")
else:
    print(last.get(field, ""))
PY
}

# Whether any line recorded that route while `loading` had that value.
route_seen() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, wanted_route, wanted_loading = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
seen = False
try:
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("route") == wanted_route and bool(row.get("loading")) == wanted_loading:
                seen = True
except FileNotFoundError:
    pass
print("yes" if seen else "no")
PY
}

# --- 1. resume from the home page, then close -------------------------------
# The documented repro: play once so a history record exists, then resume it and
# close the player. Before the fix the return route had been overwritten with
# `.loading` and the app stayed on «正在准备播放…».
dir="$OUT/resume-close"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" \
  "$APP" --open "$LOCAL" --quit-after 5 >"$dir/seed.log" 2>&1 || true
OPENFUSE_SUPPORT_DIR="$dir" \
  "$APP" --resume-first --reopen-test --route-log "$dir/route.jsonl" \
  --capture-ui "$dir/after-close.png" --ui-after 8 --quit-after 10 \
  >"$dir/app.log" 2>&1 || true
check "$(route_seen "$dir/route.jsonl" player false)" "yes" "resume played before closing"
check "$(route_field "$dir/route.jsonl" route)" "home" "resume close returns to the home page"
check "$(route_field "$dir/route.jsonl" loading)" "false" "no loading spinner after resume close"
if [[ ! -s "$dir/after-close.png" ]]; then
  echo "FAIL resume close: no screenshot"
  FAIL=1
fi

# --- 2. open a local file, then close --------------------------------------
# The other entry point that must return to the home page. `--close-after`
# closes exactly like the close button, without `--reopen-test` reopening the
# file again.
dir="$OUT/local-close"; mkdir -p "$dir"
OPENFUSE_SUPPORT_DIR="$dir" \
  "$APP" --open "$LOCAL" --close-after 4 --route-log "$dir/route.jsonl" \
  --capture-ui "$dir/after-close.png" --ui-after 7 --quit-after 8 \
  >"$dir/app.log" 2>&1 || true
check "$(route_seen "$dir/route.jsonl" player false)" "yes" "local file played before closing"
check "$(route_field "$dir/route.jsonl" route)" "home" "local close returns to the home page"
if [[ ! -s "$dir/after-close.png" ]]; then
  echo "FAIL local close: no screenshot"
  FAIL=1
fi

# --- 3. cancel and retry while loading keep their behaviour ----------------
# A delayed PROPFIND gives a real loading phase: the resume request is still in
# flight when the script cancels it.
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
ROOT="$OUT/dav-root"
mkdir -p "$ROOT/Shows/Season 1"
cp Fixtures/generated/video.mkv "$ROOT/Shows/Season 1/episode.mkv"

dir="$OUT/loading-cancel"; mkdir -p "$dir"
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" >"$dir/server-fast.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
for _ in {1..40}; do
  curl -sS --max-time 1 -X PROPFIND -H 'Depth: 0' "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1 && break
  sleep 0.25
done
# Seed a history record that belongs to this WebDAV source.
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Fixture \
  --webdav-user admin --webdav-pass test --webdav-path "Shows/Season 1/episode.mkv" \
  --quit-after 9 >"$dir/seed.log" 2>&1 || true
kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true

# Same port, but every PROPFIND now waits, so the resume stays on the loading page.
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" --propfind-delay 8 \
  >"$dir/server-slow.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 0.5
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --resume-first --cancel-loading-after 2.0 --route-log "$dir/route.jsonl" \
  --capture-ui "$dir/after-cancel.png" --ui-after 4 --quit-after 6 \
  >"$dir/app.log" 2>&1 || true
check "$(route_seen "$dir/route.jsonl" loading true)" "yes" "cancel: the loading page was really shown"
check "$(route_field "$dir/route.jsonl" route)" "home" "cancel during loading returns to the home page"
kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true

# --- 4. a failed resume stays on the error page, and 重试 keeps it there -----
# The record is seeded against a live fixture, which is then stopped: the resume
# cannot reach the source at all. 重试 must fail the same way instead of quietly
# dropping back to the home page.
dir="$OUT/loading-retry"; mkdir -p "$dir"
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$PORT" >"$dir/server-seed.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
for _ in {1..40}; do
  curl -sS --max-time 1 -X PROPFIND -H 'Depth: 0' "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1 && break
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Down \
  --webdav-user admin --webdav-pass test --webdav-path "Shows/Season 1/episode.mkv" \
  --quit-after 9 >"$dir/seed.log" 2>&1 || true
kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true
OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --resume-first --retry-loading-after 3.0 --route-log "$dir/route.jsonl" \
  --capture-ui "$dir/after-retry.png" --ui-after 5 --quit-after 7 \
  >"$dir/app.log" 2>&1 || true
check "$(route_seen "$dir/route.jsonl" loading true)" "yes" "failed resume shows the loading page"
check "$(route_field "$dir/route.jsonl" route)" "loading" "failed resume stays on the loading page"
if [[ -z "$(route_field "$dir/route.jsonl" error)" ]]; then
  echo "FAIL failed resume: the error page carries no message"
  FAIL=1
else
  echo "ok   failed resume: error message kept after 重试: $(route_field "$dir/route.jsonl" error)"
fi
if [[ ! -s "$dir/after-retry.png" ]]; then
  echo "FAIL failed resume: no screenshot"
  FAIL=1
fi

# --- 5. the captures match the logged page ---------------------------------
# Case 1 resumes from the home page and `--reopen-test`'s reopen closure is empty
# for that entry point, so the 8 s capture is the page the player returned to.
if [[ "$(route_field "$OUT/resume-close/route.jsonl" player)" != "" ]]; then
  echo "FAIL resume close: a player was still open when the screenshot was taken"
  FAIL=1
fi

if [[ "$FAIL" != "0" ]]; then
  echo "FAIL: close-return-route"
  exit 1
fi
echo "PASS: resume close, local close, cancel during loading, retry after failure"
echo "captures: $OUT"
