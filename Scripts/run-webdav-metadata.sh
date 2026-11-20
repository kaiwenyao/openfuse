#!/bin/bash
# M3f WebDAV NFO + authenticated poster cache acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/webdav-metadata"
PORT=8114
SUPPORT="$OUT/support"
if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT"; mkdir -p "$SUPPORT"
python3 Tools/webdav_fixture.py --setup --port "$PORT" --log "$OUT/server.log" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test -X PROPFIND -H "Depth: 0" "http://127.0.0.1:$PORT/dav/" >/dev/null 2>&1; then break; fi
  sleep 0.25
done

OPENFUSE_SUPPORT_DIR="$SUPPORT" OPENFUSE_WEBDAV_PASSWORD=test "$APP" \
  --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-user test --webdav-name fixture \
  --webdav-scan --library-report "$OUT/scan.json" --capture-ui "$OUT/library.png" \
  --ui-after 8 --quit-after 10 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-work "示例剧" \
  --capture-ui "$OUT/detail.png" --ui-after 4 --quit-after 6 >"$OUT/app.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
report = json.load(open(os.path.join(out, "scan.json"), encoding="utf-8"))
errors = []
if report["rawWorks"] != 2 or report["rawEpisodes"] != 2:
    errors.append(f"counts {report['rawWorks']}/{report['rawEpisodes']}")
items = {item["title"]: item for item in report["items"]}
movie = items.get("OpenFuse Fixture · WebDAV NFO")
series = items.get("示例剧 · WebDAV NFO")
if movie is None or series is None:
    errors.append(f"titles {list(items)}")
else:
    if not movie["poster"].startswith("file:") or not os.path.exists(movie["poster"][5:]):
        errors.append(f"movie poster {movie['poster']}")
    if "movie.nfo" not in movie["overview"]:
        errors.append("movie NFO overview missing")
    if not series["poster"].startswith("file:") or not os.path.exists(series["poster"][5:]):
        errors.append(f"series poster {series['poster']}")
    if "tvshow.nfo" not in series["overview"]:
        errors.append("series NFO overview missing")
    if series["episodes"][0]["title"] != "第 1 集 · WebDAV NFO":
        errors.append(f"episode NFO title {series['episodes'][0]['title']}")
for name in ["library.png", "detail.png"]:
    if not os.path.exists(os.path.join(out, name)):
        errors.append(f"missing capture {name}")
cache = os.path.join(out, "support", "PosterCache")
if not os.path.isdir(cache) or len(os.listdir(cache)) < 2:
    errors.append("poster cache missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: WebDAV NFO titles/overview/episode title, authenticated posters cached")
print(f"captures: {out}")
PY
