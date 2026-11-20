#!/bin/bash
# M5 Plex: source add/scan, poster library, library playback.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/plex-acceptance"
PORT=32400
TOKEN="plex-test-token"
if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT"
python3 Tools/plex_fixture.py --port "$PORT" --token "$TOKEN" --log "$OUT/plex.log" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$PORT/library/sections?X-Plex-Token=$TOKEN" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_PLEX_TOKEN="$TOKEN" "$APP" \
  --plex-url "http://127.0.0.1:$PORT" --plex-token "$TOKEN" --plex-name Plex \
  --library-report "$OUT/library.json" --capture-ui "$OUT/library.png" \
  --ui-after 5 --quit-after 7 >"$OUT/app.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
for item in data["items"]:
    if item["title"] == "Plex 示例剧":
        print(item["episodes"][0]["id"]); break
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_PLEX_TOKEN="$TOKEN" "$APP" \
  --library-play "$EPISODE" --freeze-at 9.9 --capture "$OUT/play.png" \
  --capture-after 14 --report "$OUT/play.json" --quit-after 16 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_PLEX_TOKEN="$TOKEN" "$APP" \
  --library-play "$EPISODE" --seek 59 --report "$OUT/scrobble.json" \
  --capture-after 9 --quit-after 11 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
library = json.load(open(os.path.join(out, "library.json")))
if library["rawWorks"] != 2 or library["rawEpisodes"] != 3:
    errors.append(f"counts {library['rawWorks']}/{library['rawEpisodes']}")
if not all(item["sourceKind"] == "plex" for item in library["items"]):
    errors.append("sourceKind not plex")
if not any(item["poster"].startswith("plex:") for item in library["items"]):
    errors.append("plex poster refs missing")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("sourceKind") != "plex" or not 9.8 <= play.get("position", 0) <= 10.1:
    errors.append(f"play {play.get('sourceKind')} {play.get('position')}")
for name in ["library.png", "play.png"]:
    if not os.path.exists(os.path.join(out, name)):
        errors.append(f"missing {name}")
log = open(os.path.join(out, "plex.log"), encoding="utf-8").read()
if "/:/timeline" not in log or "state=playing" not in log:
    errors.append("Plex timeline playing not reported")
if "state=paused" not in log:
    errors.append("Plex timeline paused not reported")
if "/:/scrobble" not in log:
    errors.append("Plex scrobble not reported")
if "state=stopped" not in log:
    errors.append("Plex timeline stopped not reported")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Plex scan 2 works/3 episodes, poster refs, sourceKind plex, playback 9.9s")
PY
