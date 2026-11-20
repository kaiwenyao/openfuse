#!/bin/bash
# M3g library type filter and sort acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/library-filters"
SUPPORT="$OUT/support"
if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
python3 Tools/make_library_fixture.py >/dev/null
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT"; mkdir -p "$SUPPORT"
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --scan-local "$PWD/build/library-fixture" \
  --library-report "$OUT/base.json" --quit-after 2 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-filter movie --library-sort year \
  --library-report "$OUT/movies.json" --capture-ui "$OUT/movies.png" \
  --ui-after 3 --quit-after 4 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-filter series --library-sort episodes \
  --library-report "$OUT/series.json" --quit-after 2 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-sort title --library-search "示例" \
  --library-report "$OUT/search.json" --quit-after 2 >"$OUT/app.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
def load(name): return json.load(open(os.path.join(out, name), encoding="utf-8"))
errors = []
if load("movies.json")["visible"] != ["OpenFuse Fixture"]:
    errors.append(f"movie filter {load('movies.json')['visible']}")
series = load("series.json")["visible"]
if series != ["示例剧", "另一部剧 · 本地 NFO"]:
    errors.append(f"series sort {series}")
search = load("search.json")["visible"]
if search != ["示例剧"]:
    errors.append(f"search {search}")
if not os.path.exists(os.path.join(out, "movies.png")):
    errors.append("missing capture")
if errors:
    print("FAIL")
    for e in errors: print(" -", e)
    sys.exit(1)
print("PASS: type filter, episode-count sort, title sort, search")
print(f"captures: {out}")
PY
