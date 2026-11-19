#!/bin/bash
# End-to-end WebDAV acceptance on the local fixture server.
#
#   Scripts/run-webdav-acceptance.sh
#
# Covers: add source, browse (protocol), remote playback with remote ASS,
# remote seek through HTTP Range with the old request cancelled, and resume
# from the home "continue watching" record.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/webdav-acceptance"
PORT=8103
THROTTLE_PORT=8104
SUBS="Movies/OpenFuse Fixture (2026)/OpenFuse Fixture.mkv"

if [[ ! -f "$FIXTURE" ]]; then Scripts/make_fixtures.sh; fi
Scripts/build-app.sh >/dev/null
swift build --product openfuse-probe >/dev/null

rm -rf "$OUT"; mkdir -p "$OUT"
: > "$OUT/server.log"; : > "$OUT/server-throttle.log"

python3 Tools/webdav_fixture.py --setup --port "$PORT" --log "$OUT/server.log" >"$OUT/server.out" 2>&1 &
SERVER=$!
python3 Tools/webdav_fixture.py --port "$THROTTLE_PORT" --log "$OUT/server-throttle.log" --throttle-kbps 700 >"$OUT/server-throttle.out" 2>&1 &
THROTTLE=$!
trap 'kill "$SERVER" "$THROTTLE" 2>/dev/null || true' EXIT

for _ in {1..30}; do
  if curl -sS --max-time 1 -u test:test -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

run_app() {
  local support="$1"; shift
  mkdir -p "$support"
  OPENFUSE_SUPPORT_DIR="$support" OPENFUSE_WEBDAV_PASSWORD=test "$APP" "$@" >"$OUT/app.log" 2>&1 || true
  sleep 0.5
}

# 1. Remote playback + remote external subtitle.
run_app "$OUT/support-play" \
  --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-user test --webdav-name fixture \
  --webdav-path "$SUBS" --freeze-at 9.9 \
  --capture "$OUT/remote-frame.png" --capture-after 14 \
  --report "$OUT/remote-play.json" --quit-after 16

# 2. Remote seek on a throttled server so the initial GET cannot buffer the file.
run_app "$OUT/support-seek" \
  --webdav-url "http://127.0.0.1:$THROTTLE_PORT/dav/" --webdav-user test --webdav-name throttled \
  --webdav-path "$SUBS" --seek 40 --freeze-at 41 \
  --capture "$OUT/remote-seek.png" --capture-after 32 \
  --report "$OUT/remote-seek.json" --quit-after 34

# 3. Resume from the saved position through the home record path (no --webdav args).
run_app "$OUT/support-resume" \
  --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-user test --webdav-name fixture \
  --webdav-path "$SUBS" --seek 20 \
  --capture-after 5 --quit-after 7
SAVED=$(python3 -c "import json;d=json.load(open('$OUT/support-resume/playback.json'));print(list(d['records'].values())[0]['position'])")
run_app "$OUT/support-resume" \
  --resume-first --capture "$OUT/remote-resume.png" --capture-after 6 \
  --report "$OUT/remote-resume.json" --quit-after 8

python3 - "$OUT" "$SAVED" <<'PY'
import json, os, sys
out, saved = sys.argv[1], float(sys.argv[2])

def load(name):
    with open(os.path.join(out, name), encoding="utf-8") as fh:
        return json.load(fh)

def video_gets(path):
    result = []
    if not os.path.exists(path):
        return result
    for line in open(path, encoding="utf-8"):
        try:
            event = json.loads(line)
        except Exception:
            continue
        if event.get("method") == "GET" and event.get("path", "").endswith(".mkv"):
            result.append(event)
    return result

errors = []
play = load("remote-play.json")
if play.get("sourceKind") != "webdav":
    errors.append("remote-play: source is not webdav")
if not 9.8 <= play.get("position", 0) <= 10.2 or not play.get("paused"):
    errors.append(f"remote-play: unexpected position/pause {play.get('position')} {play.get('paused')}")
if not play.get("selectedSubtitle", "").endswith("OpenFuse Fixture.zh-Hans.ass"):
    errors.append(f"remote-play: remote subtitle not selected: {play.get('selectedSubtitle')}")
if play.get("duration") != 60:
    errors.append(f"remote-play: duration {play.get('duration')}")
if not os.path.exists(os.path.join(out, "remote-frame.png")):
    errors.append("remote-play: missing rendered frame")

seek = load("remote-seek.json")
if not 40.7 <= seek.get("position", 0) <= 41.4 or not seek.get("paused"):
    errors.append(f"remote-seek: unexpected position {seek.get('position')}")
gets = video_gets(os.path.join(out, "server-throttle.log"))
if not any(event.get("aborted") for event in gets):
    errors.append("remote-seek: initial GET was not cancelled")
if not any((event.get("start") or 0) > 1_000_000 for event in gets):
    errors.append("remote-seek: no mid-file Range request")
if not any(event.get("selectedSubtitle", "").endswith("zh-Hans.ass") for event in [seek]):
    errors.append("remote-seek: subtitle not selected")

resume = load("remote-resume.json")
if resume.get("position", 0) < saved + 2:
    errors.append(f"remote-resume: {resume.get('position')} did not continue from {saved}")
if resume.get("sourceKind") != "webdav":
    errors.append("remote-resume: source kind lost")

if errors:
    print("FAIL")
    for error in errors:
        print(" -", error)
    sys.exit(1)
print(f"PASS: remote playback + remote ASS, Range seek ({len(gets)} GETs), resume {saved:.3f}s")
print(f"captures: {out}")
PY
