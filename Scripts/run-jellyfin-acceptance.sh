#!/bin/bash
# End-to-end Jellyfin Direct acceptance against the local fixture.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/jellyfin-acceptance"
PORT=8107
LOG="$OUT/server.log"

if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null

rm -rf "$OUT"; mkdir -p "$OUT"
: > "$LOG"
python3 Tools/jellyfin_fixture.py --setup --port "$PORT" --log "$LOG" >"$OUT/server.out" 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT
for _ in {1..30}; do
  if curl -sS --max-time 1 "http://127.0.0.1:$PORT/System/Info/Public" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

run_app() {
  local support="$1"; shift
  mkdir -p "$support"
  OPENFUSE_SUPPORT_DIR="$support" OPENFUSE_JELLYFIN_PASSWORD=test "$APP" "$@" >"$OUT/app.log" 2>&1 || true
  sleep 0.5
}

BASE="http://127.0.0.1:$PORT"

# 1. Episode direct play with server metadata + progress.
run_app "$OUT/support-ep" \
  --jellyfin-url "$BASE" --jellyfin-user test --jellyfin-name fixture \
  --jellyfin-item ep-1 --freeze-at 9.9 \
  --capture "$OUT/episode-frame.png" --capture-after 14 \
  --report "$OUT/episode.json" --quit-after 16

# 2. Movie with an explicitly selected non-default version.
run_app "$OUT/support-movie" \
  --jellyfin-url "$BASE" --jellyfin-user test --jellyfin-name fixture \
  --jellyfin-item movie-1 --jellyfin-media ms-movie-compact --freeze-at 9.9 \
  --capture "$OUT/movie-frame.png" --capture-after 14 \
  --report "$OUT/movie.json" --quit-after 16

# 3. Re-open the episode with a fresh local store: position must come from the server.
run_app "$OUT/support-resume" \
  --jellyfin-url "$BASE" --jellyfin-user test --jellyfin-name fixture \
  --jellyfin-item ep-1 \
  --capture "$OUT/resume-frame.png" --capture-after 6 \
  --report "$OUT/resume.json" --quit-after 8

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]

def load(name):
    with open(os.path.join(out, name), encoding="utf-8") as fh:
        return json.load(fh)

def events():
    result = []
    path = os.path.join(out, "server.log")
    if not os.path.exists(path):
        return result
    for line in open(path, encoding="utf-8"):
        try:
            result.append(json.loads(line))
        except Exception:
            pass
    return result

errors = []
episode = load("episode.json")
if episode.get("sourceKind") != "jellyfin":
    errors.append("episode: source kind is not jellyfin")
if episode.get("title") != "第 1 集":
    errors.append(f"episode: title {episode.get('title')}")
if not 9.8 <= episode.get("position", 0) <= 10.2 or not episode.get("paused"):
    errors.append(f"episode: position/pause {episode.get('position')} {episode.get('paused')}")
subs = [s.get("name") for s in episode.get("subtitles", [])]
if not any("服务器字幕" in name for name in subs):
    errors.append(f"episode: server subtitle label missing: {subs}")
audio = [a.get("name") for a in episode.get("audio", [])]
if not any("服务器音轨" in name for name in audio):
    errors.append(f"episode: server audio label missing: {audio}")

movie = load("movie.json")
if not movie.get("remotePath", "").endswith("ms-movie-compact"):
    errors.append(f"movie: wrong version {movie.get('remotePath')}")

resume = load("resume.json")
if resume.get("position", 0) < 10:
    errors.append(f"resume: did not start from server position ({resume.get('position')})")

logs = events()
if not any(e.get("event") == "Playing" for e in logs):
    errors.append("server: no Playing event")
if not any(e.get("event") == "Progress" for e in logs):
    errors.append("server: no Progress event")
stops = [e for e in logs if e.get("event") == "Stopped"]
if not stops:
    errors.append("server: no Stopped event")
elif not 9.0e7 <= (stops[0].get("body", {}).get("PositionTicks") or 0) <= 1.05e8:
    errors.append(f"server: stop position {stops[0].get('body', {}).get('PositionTicks')}")
if not any("ms-movie-compact" in e.get("path", "") for e in logs):
    errors.append("server: selected movie version was not streamed")
starts = [e for e in logs if e.get("event") == "Playing"]
if len(starts) < 2 or (starts[-1].get("body", {}).get("PositionTicks") or 0) < 9.0e7:
    errors.append("server: resume start did not report the server position")

if errors:
    print("FAIL")
    for error in errors:
        print(" -", error)
    sys.exit(1)
print(f"PASS: Jellyfin direct play, server metadata, version switch, progress, server resume")
print(f"captures: {out}")
PY
