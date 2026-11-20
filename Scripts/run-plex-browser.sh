#!/bin/bash
# M5i: Plex Direct sections and movie section grid.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/plex-browser"
TOKEN=plex-test-token
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
python3 Tools/plex_fixture.py --port 32400 --log "$OUT/plex.log" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 "http://127.0.0.1:32400/library/sections?X-Plex-Token=$TOKEN" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_PLEX_TOKEN="$TOKEN" "$APP" \
  --plex-url http://127.0.0.1:32400 --plex-token "$TOKEN" --plex-browse --plex-name Plex \
  --capture-ui "$OUT/sections.png" --ui-after 5 --quit-after 7 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_PLEX_TOKEN="$TOKEN" OPENFUSE_PLEX_SECTION=1 "$APP" \
  --plex-url http://127.0.0.1:32400 --plex-token "$TOKEN" --plex-browse --plex-name Plex \
  --capture-ui "$OUT/section.png" --ui-after 6 --quit-after 8 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_PLEX_TOKEN="$TOKEN" OPENFUSE_PLEX_SECTION=1 OPENFUSE_PLEX_ITEM=101 "$APP" \
  --plex-url http://127.0.0.1:32400 --plex-token "$TOKEN" --plex-browse --plex-name Plex \
  --capture-ui "$OUT/detail.png" --ui-after 6 --quit-after 8 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_PLEX_TOKEN="$TOKEN" "$APP" \
  --plex-url http://127.0.0.1:32400 --plex-token "$TOKEN" --plex-name Plex \
  --plex-play 401 --subtitle zh-Hans --freeze-at 9.9 --capture "$OUT/play.png" \
  --capture-after 14 --report "$OUT/play.json" --quit-after 16 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
for name in ["sections.png", "section.png", "detail.png", "play.png"]:
    path = os.path.join(out, name)
    if not os.path.exists(path) or os.path.getsize(path) < 10_000:
        errors.append(f"missing/empty {name}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("sourceKind") != "plex" or not 9.8 <= play.get("position", 0) <= 10.1:
    errors.append(f"plex detail play {play.get('sourceKind')} {play.get('position')}")
if not str(play.get("selectedSubtitle", "")).startswith("mpv:"):
    errors.append(f"plex detail subtitle {play.get('selectedSubtitle')}")
if not any("Plex 外挂简体" in item.get("name", "") for item in play.get("subtitles", [])):
    errors.append("plex external subtitle missing")
log = open(os.path.join(out, "plex.log"), encoding="utf-8").read()
if "/library/sections" not in log:
    errors.append("Plex sections not requested")
if "/library/sections/1/all" not in log:
    errors.append("Plex movie section items not requested")
if "X-Plex-Token=plex-test-token" not in log:
    errors.append("Plex token missing from request log")
if "/library/metadata/401" not in log:
    errors.append("Plex detail metadata not requested")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Plex Direct sections + movie grid requested with token")
PY
