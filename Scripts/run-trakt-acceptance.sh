#!/bin/bash
# M4q: Trakt device code + search/scrobble against a local fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
PROBE=".build/debug/openfuse-probe"
OUT="$PWD/build/trakt-acceptance"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
swift build --product openfuse-probe >/dev/null
python3 Tools/trakt_fixture.py --port 8123 --log "$OUT/trakt.log" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 http://127.0.0.1:8123/search/movie >/dev/null 2>&1; then break; fi
  sleep 0.25
done
DEVICE=$("$PROBE" trakt-device http://127.0.0.1:8123 test-client test-secret)
CODE=$(python3 - "$DEVICE" <<'PY'
import json, sys
print(json.loads(sys.argv[1])["device_code"])
PY
)
"$PROBE" trakt-poll http://127.0.0.1:8123 test-client test-secret "$CODE" >"$OUT/token.json"
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_TRAKT_BASE_URL=http://127.0.0.1:8123 \
OPENFUSE_TRAKT_CLIENT_ID=test-client \
OPENFUSE_TRAKT_TOKEN=trakt-test-token \
"$APP" --open Fixtures/generated/openfuse-fixture.mkv --seek 58 --freeze-at 59.9 \
  --capture "$OUT/play.png" --capture-after 12 --report "$OUT/play.json" \
  --quit-after 14 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --scan-local build/library-fixture \
  --library-report "$OUT/series-library.json" --quit-after 3 >"$OUT/series-scan.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/series-library.json"))
for item in data["items"]:
    if item["title"] == "示例剧":
        print(item["episodes"][0]["id"]); break
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_TRAKT_BASE_URL=http://127.0.0.1:8123 \
OPENFUSE_TRAKT_CLIENT_ID=test-client \
OPENFUSE_TRAKT_TOKEN=trakt-test-token \
"$APP" --library-play "$EPISODE" --seek 58 --freeze-at 59.9 \
  --capture "$OUT/show.png" --capture-after 12 --report "$OUT/show.json" \
  --quit-after 14 >"$OUT/show.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
log = open(os.path.join(out, "trakt.log"), encoding="utf-8").read()
for needle in ["/oauth/device/code", "/oauth/device/token", "/search/movie", "/search/show", "/scrobble/start", "/scrobble/stop"]:
    if needle not in log:
        errors.append(f"missing {needle}")
if '"episode"' not in log or ('"season": 1' not in log and '"season":1' not in log):
    errors.append("show episode payload missing")
if '"progress": 99.' not in log:
    errors.append("stop progress near 100 missing")
token = json.load(open(os.path.join(out, "token.json")))
if token.get("access_token") != "trakt-test-token":
    errors.append(f"token {token}")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("position", 0) < 59:
    errors.append(f"position {play.get('position')}")
show = json.load(open(os.path.join(out, "show.json")))
if show.get("position", 0) < 59:
    errors.append(f"show position {show.get('position')}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Trakt device/token + movie/show search + episode scrobble (99.9%)")
PY
