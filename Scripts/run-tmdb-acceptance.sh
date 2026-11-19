#!/bin/bash
# M3b metadata acceptance: TMDB + NFO enrichment for local and WebDAV scans.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/tmdb-acceptance"
TMDB_PORT=8112
WEBDAV_PORT=8113
SUPPORT="$OUT/support-local"

if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
python3 Tools/make_library_fixture.py >/dev/null
Scripts/build-app.sh >/dev/null
swift test >/dev/null

rm -rf "$OUT"; mkdir -p "$SUPPORT"
: > "$OUT/tmdb.log"; : > "$OUT/webdav.log"
python3 Tools/tmdb_fixture.py --port "$TMDB_PORT" --log "$OUT/tmdb.log" >"$OUT/tmdb.out" 2>&1 &
T=$!
python3 Tools/webdav_fixture.py --setup --port "$WEBDAV_PORT" --log "$OUT/webdav.log" >"$OUT/webdav.out" 2>&1 &
W=$!
trap 'kill "$T" "$W" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$TMDB_PORT/3/search/movie?api_key=test-key&query=x" >/dev/null 2>&1 \
     && curl -sS --max-time 1 -u test:test -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$WEBDAV_PORT/dav/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

TMDB_ENV=(
  OPENFUSE_TMDB_API_KEY=test-key
  "OPENFUSE_TMDB_BASE_URL=http://127.0.0.1:$TMDB_PORT/3"
  "OPENFUSE_TMDB_IMAGE_BASE=http://127.0.0.1:$TMDB_PORT"
)

env "${TMDB_ENV[@]}" OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" \
  --scan-local "$PWD/build/library-fixture" \
  --library-report "$OUT/local.json" --capture-ui "$OUT/local.png" \
  --ui-after 9 --quit-after 11 >"$OUT/app.log" 2>&1 || true
sleep 0.5

env "${TMDB_ENV[@]}" OPENFUSE_SUPPORT_DIR="$OUT/support-webdav" OPENFUSE_WEBDAV_PASSWORD=test "$APP" \
  --webdav-url "http://127.0.0.1:$WEBDAV_PORT/dav/" --webdav-user test --webdav-name fixture \
  --webdav-scan --library-report "$OUT/webdav.json" --capture-ui "$OUT/webdav.png" \
  --ui-after 9 --quit-after 11 >"$OUT/app.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]

def load(name):
    with open(os.path.join(out, name), encoding="utf-8") as fh:
        return json.load(fh)

errors = []
local = load("local.json")
titles = {item["title"] for item in local["items"]}
for expected in ["OpenFuse Fixture: TMDB Cut", "另一部剧 · 本地 NFO", "示例剧：TMDB 版"]:
    if expected not in titles:
        errors.append(f"local: missing title {expected}")
if local["rawWorks"] != 3 or len(local["groups"]) != 3:
    errors.append(f"local: counts {local['rawWorks']} groups {len(local['groups'])}")
posters = {item["title"]: item["poster"] for item in local["items"]}
if not posters.get("OpenFuse Fixture: TMDB Cut", "").startswith("remote:"):
    errors.append("local: TMDB movie poster missing")
if not posters.get("示例剧：TMDB 版", "").startswith("remote:"):
    errors.append("local: TMDB series poster missing")
if not posters.get("另一部剧 · 本地 NFO", "").startswith("file:"):
    errors.append("local: NFO poster missing")
overviews = {item["title"]: item.get("overview", "") for item in local["items"]}
if "TMDB fixture overview" not in overviews.get("OpenFuse Fixture: TMDB Cut", ""):
    errors.append("local: TMDB overview missing")
if "tvshow.nfo" not in overviews.get("另一部剧 · 本地 NFO", ""):
    errors.append("local: NFO overview missing")

webdav = load("webdav.json")
wtitles = {item["title"] for item in webdav["items"]}
if wtitles != {"OpenFuse Fixture: TMDB Cut", "示例剧：TMDB 版"}:
    errors.append(f"webdav: titles {wtitles}")
for item in webdav["items"]:
    if not item["poster"].startswith("remote:"):
        errors.append(f"webdav: poster not enriched for {item['title']}")

for name in ["local.png", "webdav.png"]:
    if not os.path.exists(os.path.join(out, name)):
        errors.append(f"missing capture {name}")
log = open(os.path.join(out, "tmdb.log"), encoding="utf-8").read()
if "/3/search/movie" not in log or "/3/search/tv" not in log:
    errors.append("tmdb: search endpoints not called")

if errors:
    print("FAIL")
    for error in errors:
        print(" -", error)
    sys.exit(1)
print("PASS: TMDB movie/TV enrichment, NFO precedence, WebDAV posters, local/remote UI")
print(f"captures: {out}")
PY
