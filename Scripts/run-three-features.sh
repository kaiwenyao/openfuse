#!/bin/bash
# Acceptance for the three 0.6.0 features:
#   1. subtitle time offset (direction/value, immediate, per track, persisted),
#   2. same-folder video list (local + WebDAV, order, duplicate versions,
#      switching, fullscreen),
#   3. WebDAV directory metadata (TMDB + OMDb ratings, episodes, stills,
#      detail overlay, fail-soft without metadata).
#
#   Scripts/run-three-features.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/three-features"
ROOT="$OUT/root"
mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
swift test >/dev/null

# --- fixtures ------------------------------------------------------------
rm -rf "$ROOT"; mkdir -p \
  "$ROOT/Game of Thrones/Season 1/Sub" \
  "$ROOT/进击的巨人/Season 3" \
  "$ROOT/Inception (2010)"
ffmpeg -v error -y -i "$FIXTURE" -t 20 -vf scale=640:360 \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 96k "$OUT/small.mp4"
GOT="$ROOT/Game of Thrones/Season 1"
cp "$OUT/small.mp4" "$GOT/Game.of.Thrones.S01E01.Winter.Is.Coming.1080p.mkv"
cp "$OUT/small.mp4" "$GOT/Game.of.Thrones.S01E02.The.Kingsroad.1080p.mkv"
cp "$OUT/small.mp4" "$GOT/Game.of.Thrones.S01E02.The.Kingsroad.2160p.mkv"
cp "$OUT/small.mp4" "$GOT/Game.of.Thrones.S01E10.Fire.and.Blood.1080p.mkv"
cp "$OUT/small.mp4" "$GOT/Sub/Extra.mkv"
echo "1" > "$GOT/Game.of.Thrones.S01E02.The.Kingsroad.zh-Hans.srt"
echo "<tvshow/>" > "$GOT/tvshow.nfo"
printf '\x89PNG\r\n' > "$GOT/poster.jpg"

AOT="$ROOT/进击的巨人/Season 3"
cp "$OUT/small.mp4" "$AOT/Attack.on.Titan.S03E13.1080p.mkv"
for lang in zh-Hans zh-Hant; do
  cat > "$AOT/Attack.on.Titan.S03E13.$lang.ass" <<ASS
[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,36,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:10.00,0:00:12.00,Default,,0,0,0,,AOT-$lang 10
ASS
done
cp "$OUT/small.mp4" "$ROOT/Inception (2010)/Inception.2010.1080p.mkv"
mkdir -p "$OUT/offset"
ffmpeg -v error -y -i "$FIXTURE" -t 15 -vf scale=1280:720 \
  -c:v libx264 -preset ultrafast -c:a aac "$OUT/offset/sample.mp4"
cat > "$OUT/offset/sample.zh-Hans.srt" <<'SRT'
1
00:00:10,000 --> 00:00:11,500
OFFSET-MARKER 10.0
SRT

free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }
META_PORT=$(free_port); DAV_PORT=$(free_port)
python3 Scripts/metadata_fixture.py --port "$META_PORT" >"$OUT/metadata-server.log" 2>&1 &
META_PID=$!
python3 Scripts/webdav_fixture.py --root "$ROOT" --port "$DAV_PORT" >"$OUT/webdav-server.log" 2>&1 &
DAV_PID=$!
trap 'kill "$META_PID" "$DAV_PID" >/dev/null 2>&1 || true' EXIT
sleep 1

META_ENV=(OPENFUSE_TMDB_API_KEY=test
  OPENFUSE_TMDB_BASE_URL="http://127.0.0.1:$META_PORT/3"
  OPENFUSE_TMDB_IMAGE_BASE="http://127.0.0.1:$META_PORT/img"
  OPENFUSE_OMDB_API_KEY=test
  OPENFUSE_OMDB_BASE_URL="http://127.0.0.1:$META_PORT/omdb")
DAV_BASE="http://127.0.0.1:$DAV_PORT/dav/"

FAIL=0
check() { if [[ "$1" != "$2" ]]; then echo "FAIL $3: expected $2, got $1"; FAIL=1; else echo "ok   $3: $1"; fi; }
report() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "$@"; }

run_offset() {
  local name="$1" dir="$2"; shift 2
  rm -rf "$dir"; mkdir -p "$dir"
  OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
    "$APP" --open "$OUT/offset/sample.mp4" "$@" --report "$dir/report.json" --capture-after 14 --quit-after 16 \
    >"$dir/app.log" 2>&1 || true
}

# 1) Subtitle offset: late / early / hidden, then reopen persistence.
run_offset late "$OUT/offset-late" --sub-delay 1.5 --freeze-at 12
check "$(report "$OUT/offset-late/report.json" subText)" "OFFSET-MARKER 10.0" "late +1.5s shows at 12.0s"
run_offset early "$OUT/offset-early" --sub-delay -1.0 --freeze-at 9.5
check "$(report "$OUT/offset-early/report.json" subText)" "OFFSET-MARKER 10.0" "early -1.0s shows at 9.5s"
run_offset hidden "$OUT/offset-hidden" --sub-delay 1.5 --freeze-at 10.2
check "$(report "$OUT/offset-hidden/report.json" subText)" "" "late +1.5s hides at 10.2s"

OPENFUSE_SUPPORT_DIR="$OUT/offset-late" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$OUT/offset/sample.mp4" --freeze-at 12 --report "$OUT/offset-late/reopen.json" \
  --capture-after 14 --quit-after 16 >"$OUT/offset-late/reopen.log" 2>&1 || true
check "$(report "$OUT/offset-late/reopen.json" subDelay)" "1.5" "offset restored after reopen"
check "$(report "$OUT/offset-late/reopen.json" subDelaySummary)" "延后 1.5 秒" "direction/value shown"

# AoT 简繁 tracks keep independent offsets.
AOT_FILE="$AOT/Attack.on.Titan.S03E13.1080p.mkv"
run_aot() {
  local dir="$OUT/aot-offsets"
  OPENFUSE_SUPPORT_DIR="$dir" OPENFUSE_FORCE_CONTROLS=1 \
    "$APP" --open "$AOT_FILE" "$@" --report "$dir/report.json" --capture-after 4 --quit-after 6 \
    >"$dir/app.log" 2>&1 || true
}
rm -rf "$OUT/aot-offsets"; mkdir -p "$OUT/aot-offsets"
run_aot --sub-delay 1.5
run_aot --subtitle zh-Hant --sub-delay 2
run_aot --subtitle zh-Hans
check "$(report "$OUT/aot-offsets/report.json" subDelay)" "1.5" "simplified track keeps 1.5"
run_aot --subtitle zh-Hant
check "$(report "$OUT/aot-offsets/report.json" subDelay)" "2" "traditional track keeps 2.0"

# 2) Same-folder list: local order/duplicates, switching, fullscreen WebDAV.
GOT_E2="$GOT/Game.of.Thrones.S01E02.The.Kingsroad.1080p.mkv"
OPENFUSE_SUPPORT_DIR="$OUT/folder-local" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$GOT_E2" --folder-list --capture-window "$OUT/folder-local.png" \
  --ui-after 5 --report "$OUT/folder-local.json" --capture-after 5 --quit-after 7 \
  >"$OUT/folder-local.log" 2>&1 || true
check "$(report "$OUT/folder-local.json" folderCount)" "4" "local folder count"
python3 - "$OUT/folder-local.json" <<'PY' && echo "ok   local order E1,E2,E2,E10" || { echo "FAIL local order"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
titles = d.get("folderTitles") or []
ok = len(titles) == 4 and titles[0].startswith("S1 · E1") and titles[1].startswith("S1 · E2") \
     and titles[2].startswith("S1 · E2") and titles[3].startswith("S1 · E10")
sys.exit(0 if ok else 1)
PY
check "$(report "$OUT/folder-local.json" currentFolderVideoID)" "$GOT_E2" "current item marked"

OPENFUSE_SUPPORT_DIR="$OUT/folder-switch" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$GOT_E2" --folder-select E10 --report "$OUT/folder-switch.json" \
  --capture-after 6 --quit-after 8 >"$OUT/folder-switch.log" 2>&1 || true
python3 - "$OUT/folder-switch.json" <<'PY' && echo "ok   local switch to E10" || { echo "FAIL local switch"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if "E10" in (d.get("currentFolderVideoID") or "") and (d.get("position") or 0) > 0 else 1)
PY

DAV_E2="Game of Thrones/Season 1/Game.of.Thrones.S01E02.The.Kingsroad.1080p.mkv"
env "${META_ENV[@]}" \
  OPENFUSE_SUPPORT_DIR="$OUT/folder-dav" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "$DAV_BASE" --webdav-name T --webdav-user admin --webdav-pass test \
  --webdav-path "$DAV_E2" --folder-select E10 --fullscreen --capture-window "$OUT/folder-dav.png" \
  --ui-after 7 --report "$OUT/folder-dav.json" --capture-after 7 --quit-after 9 \
  >"$OUT/folder-dav.log" 2>&1 || true
check "$(report "$OUT/folder-dav.json" folderCount)" "4" "WebDAV folder count"
check "$(report "$OUT/folder-dav.json" isFullScreen)" "True" "fullscreen preserved while switching"
python3 - "$OUT/folder-dav.json" <<'PY' && echo "ok   WebDAV switch/metadata titles" || { echo "FAIL WebDAV switch"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if "E10" in (d.get("currentFolderVideoID") or "")
         and len(d.get("folderThumbnails") or []) >= 4 else 1)
PY

# 3) Metadata: GoT browse + detail, AoT detail, movie, offline fail-soft.
browse() {
  local name="$1" path="$2"; shift 2
  rm -rf "$OUT/$name"; mkdir -p "$OUT/$name"
  env "${META_ENV[@]}" OPENFUSE_DEBUG_METADATA=1 OPENFUSE_SUPPORT_DIR="$OUT/$name" \
    OPENFUSE_WEBDAV_PASSWORD=test "$@" \
    "$APP" --webdav-url "$DAV_BASE" --webdav-name T --webdav-user admin --webdav-pass test \
    --webdav-browse-path "$path" --webdav-browse --capture-ui "$OUT/$name/ui.png" \
    --ui-after 8 --quit-after 10 >"$OUT/$name/app.log" 2>&1 || true
}
browse got "Game of Thrones/Season 1" OPENFUSE_SHOW_METADATA_DETAIL=1
python3 - "$OUT/got/Acceptance/metadata.json" <<'PY' && echo "ok   GoT metadata + ratings + episodes" || { echo "FAIL GoT metadata"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
work = d.get("work", {})
ratings = work.get("externalRatings") or []
eps = d.get("episodes") or []
ok = work.get("title") == "Game of Thrones" and work.get("year") == 2011 \
     and work.get("tmdbRating") is not None and any("IMDb" in r for r in ratings) \
     and any("烂番茄" in r for r in ratings) and any("Metacritic" in r for r in ratings) \
     and len(eps) == 3 and any(e.get("number") == 10 and e.get("title") == "Fire and Blood" for e in eps)
sys.exit(0 if ok else 1)
PY

browse aot "进击的巨人/Season 3" OPENFUSE_SHOW_METADATA_DETAIL=1
python3 - "$OUT/aot/Acceptance/metadata.json" <<'PY' && echo "ok   AoT S03E13 metadata" || { echo "FAIL AoT metadata"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
eps = d.get("episodes") or []
ok = d.get("work", {}).get("title") == "进击的巨人" and any(
    e.get("season") == 3 and e.get("number") == 13 and e.get("title") == "地下室" for e in eps)
sys.exit(0 if ok else 1)
PY

browse movie "Inception (2010)"
python3 - "$OUT/movie/Acceptance/metadata.json" <<'PY' && echo "ok   movie metadata + external ratings" || { echo "FAIL movie metadata"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
work = d.get("work", {})
sys.exit(0 if work.get("title") == "盗梦空间" and work.get("year") == 2010
         and any("IMDb" in r for r in (work.get("externalRatings") or [])) else 1)
PY

# Offline: no keys, directory still browsable and playable.
rm -rf "$OUT/offline"; mkdir -p "$OUT/offline"
OPENFUSE_SUPPORT_DIR="$OUT/offline" OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url "$DAV_BASE" --webdav-name T --webdav-user admin --webdav-pass test \
  --webdav-browse-path "Game of Thrones/Season 1" --webdav-browse \
  --capture-ui "$OUT/offline/ui.png" --ui-after 6 --quit-after 8 >"$OUT/offline/app.log" 2>&1 || true
[[ -s "$OUT/offline/ui.png" ]]; check "$?" "0" "offline directory still renders"
OPENFUSE_SUPPORT_DIR="$OUT/offline" OPENFUSE_WEBDAV_PASSWORD=test OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --webdav-url "$DAV_BASE" --webdav-name T --webdav-user admin --webdav-pass test \
  --webdav-path "$DAV_E2" --folder-list --report "$OUT/offline/play.json" \
  --capture-after 6 --quit-after 8 >"$OUT/offline/play.log" 2>&1 || true
[[ "$(report "$OUT/offline/play.json" position)" != "None" ]]; check "$?" "0" "offline playback works"
check "$(report "$OUT/offline/play.json" folderCount)" "4" "offline folder list works"

if [[ "$FAIL" != "0" ]]; then
  echo "FAIL: three features"
  exit 1
fi
echo "PASS: subtitle offsets, same-folder list, WebDAV metadata, offline fallback"
echo "captures: $OUT"
