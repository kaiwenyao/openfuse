#!/bin/bash
# TMDB search fixture checks.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${TMDB_TEST_PORT:-8111}"
PROBE=".build/debug/openfuse-probe"
swift build --product openfuse-probe >/dev/null
python3 Tools/tmdb_fixture.py --port "$PORT" >build/tmdb-test.log 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..30}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$PORT/3/search/movie?api_key=test-key&query=x" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
export OPENFUSE_TMDB_API_KEY=test-key
export OPENFUSE_TMDB_BASE_URL="http://127.0.0.1:$PORT/3"
export OPENFUSE_TMDB_IMAGE_BASE="http://127.0.0.1:$PORT"
"$PROBE" tmdb "OpenFuse Fixture" 2026 > build/tmdb-movie.json
"$PROBE" tmdb "示例剧" 2026 tv > build/tmdb-tv.json
python3 - <<'PY'
import json
movie = json.load(open("build/tmdb-movie.json"))
tv = json.load(open("build/tmdb-tv.json"))
assert movie["title"] == "OpenFuse Fixture: TMDB Cut", movie
assert movie["poster"].endswith("/poster-movie.jpg"), movie
assert tv["title"] == "示例剧：TMDB 版", tv
assert tv["poster"].endswith("/poster-series.jpg"), tv
print("PASS: TMDB movie/TV search, poster URLs")
PY
OPENFUSE_TMDB_API_KEY=wrong "$PROBE" tmdb "OpenFuse Fixture" 2026 > build/tmdb-wrong.json
python3 - <<'PY'
import json
assert json.load(open("build/tmdb-wrong.json")) == {}
print("PASS: invalid API key returns no match")
PY
