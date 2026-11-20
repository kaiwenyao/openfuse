#!/bin/bash
# M3 library acceptance: local scan, Jellyfin/WebDAV aggregation, search,
# series detail and playback from the library.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/library-acceptance"
JF_PORT=8108
WEBDAV_PORT=8109
LOCAL_ROOT="$PWD/build/library-fixture"
SUPPORT="$OUT/support"

if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
python3 Tools/make_library_fixture.py >/dev/null
Scripts/build-app.sh >/dev/null
swift test >/dev/null

rm -rf "$OUT"; mkdir -p "$SUPPORT"
: > "$OUT/jellyfin.log"; : > "$OUT/webdav.log"

python3 Tools/jellyfin_fixture.py --setup --port "$JF_PORT" --log "$OUT/jellyfin.log" >"$OUT/jellyfin.out" 2>&1 &
JF=$!
python3 Tools/webdav_fixture.py --setup --port "$WEBDAV_PORT" --log "$OUT/webdav.log" >"$OUT/webdav.out" 2>&1 &
WD=$!
trap 'kill "$JF" "$WD" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$JF_PORT/System/Info/Public" >/dev/null 2>&1 \
     && curl -sS --max-time 1 -u test:test -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$WEBDAV_PORT/dav/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

run_app() {
  local support="$1"; shift
  mkdir -p "$support"
  "$APP" "$@" >"$OUT/app.log" 2>&1 || true
  sleep 0.5
}

# 1. Local scan.
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --scan-local "$LOCAL_ROOT" \
  --library-report "$OUT/local.json" --capture-ui "$OUT/library-local.png" \
  --ui-after 5 --quit-after 7 >"$OUT/app.log" 2>&1 || true
sleep 0.5

# 2. Jellyfin scan into the same library.
OPENFUSE_SUPPORT_DIR="$SUPPORT" OPENFUSE_JELLYFIN_PASSWORD=test "$APP" \
  --jellyfin-url "http://127.0.0.1:$JF_PORT" --jellyfin-user test --jellyfin-name fixture \
  --jellyfin-scan --library-report "$OUT/aggregate.json" --quit-after 7 \
  >"$OUT/app.log" 2>&1 || true
sleep 0.5

# 3. WebDAV scan into the same library.
OPENFUSE_SUPPORT_DIR="$SUPPORT" OPENFUSE_WEBDAV_PASSWORD=test "$APP" \
  --webdav-url "http://127.0.0.1:$WEBDAV_PORT/dav/" --webdav-user test --webdav-name fixture \
  --webdav-scan --library-report "$OUT/aggregate-webdav.json" --capture-ui "$OUT/library-all.png" \
  --ui-after 5 --quit-after 7 >"$OUT/app.log" 2>&1 || true
sleep 0.5

# 4. Series detail UI.
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-work "示例剧" \
  --capture-ui "$OUT/series-detail.png" --ui-after 3 --quit-after 5 \
  >"$OUT/app.log" 2>&1 || true
sleep 0.5

# 5. Search UI.
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-search "示例" \
  --capture-ui "$OUT/library-search.png" --ui-after 3 --quit-after 5 \
  >"$OUT/app.log" 2>&1 || true
sleep 0.5

PLAY_EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
report = json.load(open(f"{sys.argv[1]}/aggregate-webdav.json"))
for work in report["items"]:
    if work["sourceKind"] == "local" and work["title"] == "示例剧":
        print(work["episodes"][0]["id"])
        break
PY
)
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-play "$PLAY_EPISODE" \
  --freeze-at 9.9 --capture "$OUT/library-play.png" --capture-after 14 \
  --report "$OUT/library-play.json" --quit-after 16 >"$OUT/app.log" 2>&1 || true
sleep 0.5

# 6. Watch state / recently played / resolution filters.
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-filter series --library-watch inProgress \
  --library-report "$OUT/watch-in-progress.json" --quit-after 3 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-sort recentlyPlayed \
  --library-report "$OUT/watch-recent.json" --quit-after 3 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-resolution hd1080 \
  --library-report "$OUT/watch-resolution.json" --quit-after 3 >"$OUT/app.log" 2>&1 || true
sleep 0.5

# 7. Spoiler protection detail.
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-work "示例剧" --library-spoiler \
  --capture-ui "$OUT/library-spoiler.png" --ui-after 3 --quit-after 5 \
  >"$OUT/app.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]

def load(name):
    with open(os.path.join(out, name), encoding="utf-8") as fh:
        return json.load(fh)

errors = []
local = load("local.json")
if (local["rawWorks"], local["rawEpisodes"]) != (3, 4):
    errors.append(f"local: counts {(local['rawWorks'], local['rawEpisodes'])}")

aggregate = load("aggregate.json")
if (aggregate["rawWorks"], aggregate["rawEpisodes"]) != (5, 7):
    errors.append(f"jellyfin aggregate: counts {(aggregate['rawWorks'], aggregate['rawEpisodes'])}")
if {item["sourceKind"] for item in aggregate["items"]} != {"local", "jellyfin"}:
    errors.append("jellyfin aggregate: missing source kinds")

aggregate2 = load("aggregate-webdav.json")
if (aggregate2["rawWorks"], aggregate2["rawEpisodes"]) != (7, 9):
    errors.append(f"webdav aggregate: counts {(aggregate2['rawWorks'], aggregate2['rawEpisodes'])}")
if {item["sourceKind"] for item in aggregate2["items"]} != {"local", "jellyfin", "webdav"}:
    errors.append("webdav aggregate: missing source kinds")
if len(aggregate2.get("groups", [])) != 3:
    errors.append(f"webdav aggregate: expected 3 merged groups, got {len(aggregate2.get('groups', []))}")
merged = {entry["key"]: entry for entry in aggregate2.get("merged", [])}
movie_key = "movie|openfuse fixture"
series_key = "series|示例剧"
if len(merged.get(movie_key, {}).get("episodes", [])) != 1:
    errors.append("merged: movie episode missing")
else:
    movie_versions = merged[movie_key]["episodes"][0]["versions"]
    if len(movie_versions) < 3:
        errors.append(f"merged: movie versions {movie_versions}")
if not merged.get(series_key, {}).get("episodes"):
    errors.append("merged: series episodes missing")
else:
    first = merged[series_key]["episodes"][0]
    if len(first["versions"]) < 3:
        errors.append(f"merged: episode versions {first['versions']}")
for item in aggregate2["items"]:
    if item["title"] == "OpenFuse Fixture (2026)" and len(item["episodes"][0]["versions"]) != 2:
        errors.append("jellyfin movie versions missing")

play = load("library-play.json")
if play.get("sourceKind") != "local" or not 9.8 <= play.get("position", 0) <= 10.2:
    errors.append(f"library play: {play.get('sourceKind')} {play.get('position')}")
if not play.get("selectedSubtitle", "").endswith(".zh-Hans.ass"):
    errors.append(f"library play: subtitle {play.get('selectedSubtitle')}")

if load("watch-in-progress.json")["visible"] != ["示例剧"]:
    errors.append(f"watch filter: {load('watch-in-progress.json')['visible']}")
if load("watch-recent.json")["visible"][:1] != ["示例剧"]:
    errors.append(f"recent sort: {load('watch-recent.json')['visible']}")
if "OpenFuse Fixture (2026)" not in load("watch-resolution.json")["visible"]:
    errors.append(f"resolution filter: {load('watch-resolution.json')['visible']}")

for name in ["library-local.png", "library-all.png", "series-detail.png", "library-search.png", "library-play.png", "library-spoiler.png"]:
    if not os.path.exists(os.path.join(out, name)):
        errors.append(f"missing capture {name}")

if errors:
    print("FAIL")
    for error in errors:
        print(" -", error)
    sys.exit(1)
print("PASS: local/Jellyfin/WebDAV scan, 7 works/9 episodes, search, details, library playback, watch/recent/resolution filters, spoiler UI")
print(f"captures: {out}")
PY
