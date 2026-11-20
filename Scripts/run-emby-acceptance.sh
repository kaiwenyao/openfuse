#!/bin/bash
# M5f Emby: add/scan (Jellyfin-compatible API) + library playback.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/emby-acceptance"
PORT=8097
USER=test
PASS=test
TOKEN=jf-test-token
if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT"
python3 Tools/jellyfin_fixture.py --port "$PORT" --mobile-sample >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$PORT/System/Info/Public" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_EMBY_USER="$USER" OPENFUSE_EMBY_PASSWORD="$PASS" "$APP" \
  --emby-url "http://127.0.0.1:$PORT" --emby-user "$USER" --emby-pass "$PASS" --emby-name Emby \
  --emby-scan --library-report "$OUT/library.json" --capture-ui "$OUT/library.png" \
  --ui-after 5 --quit-after 7 >"$OUT/app.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
for item in data["items"]:
    if item["title"] == "示例剧":
        print(item["episodes"][0]["id"]); break
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_EMBY_TOKEN="$TOKEN" "$APP" \
  --library-play "$EPISODE" --freeze-at 9.9 --capture "$OUT/play.png" \
  --capture-after 14 --report "$OUT/play.json" --quit-after 16 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
library = json.load(open(os.path.join(out, "library.json")))
if library["rawWorks"] != 2 or library["rawEpisodes"] != 3:
    errors.append(f"counts {library['rawWorks']}/{library['rawEpisodes']}")
if not all(item["sourceKind"] == "emby" for item in library["items"]):
    errors.append("sourceKind not emby")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("sourceKind") != "emby" or not 9.8 <= play.get("position", 0) <= 10.1:
    errors.append(f"play {play.get('sourceKind')} {play.get('position')}")
for name in ["library.png", "play.png"]:
    if not os.path.exists(os.path.join(out, name)):
        errors.append(f"missing {name}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Emby scan 2 works/3 episodes, sourceKind emby, playback 9.9s")
PY
