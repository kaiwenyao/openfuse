#!/bin/bash
# M5l SMB: add/scan share, cache a video, play through libmpv.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/smb-acceptance"
SHARE_DIR="$OUT/share"
PORT=1445
if [[ ! -f /opt/homebrew/lib/libsmb2.dylib ]]; then
  echo "missing libsmb2: build/install from https://github.com/sahlberg/libsmb2" >&2
  exit 1
fi
if [[ ! -x build/impacket-venv/bin/python ]]; then
  python3 -m venv build/impacket-venv
  build/impacket-venv/bin/pip install impacket >/dev/null
fi
rm -rf "$OUT"; mkdir -p "$SHARE_DIR/Movie"
cp Fixtures/generated/openfuse-fixture.mkv "$SHARE_DIR/Movie/OpenFuse.SMB.mkv"
cp build/jellyfin-fixture/movie.jpg "$SHARE_DIR/Movie/poster.jpg"
cat > "$SHARE_DIR/Movie/OpenFuse.SMB.nfo" <<'NFO'
<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>SMB NFO 电影</title>
  <year>2026</year>
  <plot>SMB NFO/海报/字幕验收。</plot>
  <poster>poster.jpg</poster>
</movie>
NFO
cp Fixtures/mobile/openfuse-mobile.zh-Hans.srt "$SHARE_DIR/Movie/OpenFuse.SMB.zh-Hans.srt"
mkdir -p "$SHARE_DIR/Shows/SMB 示例剧/Season 01" "$SHARE_DIR/Shows/SMB 示例剧/Season 02"
cp build/jellyfin-fixture/series.jpg "$SHARE_DIR/Shows/SMB 示例剧/poster.jpg"
cat > "$SHARE_DIR/Shows/SMB 示例剧/tvshow.nfo" <<'NFO'
<?xml version="1.0" encoding="UTF-8"?>
<tvshow>
  <title>SMB 示例剧</title>
  <year>2026</year>
  <plot>SMB tvshow.nfo 跨季继承验收。</plot>
  <poster>poster.jpg</poster>
</tvshow>
NFO
cp Fixtures/generated/openfuse-fixture.mkv "$SHARE_DIR/Shows/SMB 示例剧/Season 01/SMB 示例剧.S01E01.mkv"
cp Fixtures/mobile/openfuse-mobile.zh-Hans.srt "$SHARE_DIR/Shows/SMB 示例剧/Season 01/SMB 示例剧.S01E01.zh-Hans.srt"
cp Fixtures/generated/openfuse-fixture.mkv "$SHARE_DIR/Shows/SMB 示例剧/Season 02/SMB 示例剧.S02E01.mkv"
cat > "$SHARE_DIR/Shows/SMB 示例剧/Season 01/SMB 示例剧.S01E01.nfo" <<'NFO'
<?xml version="1.0" encoding="UTF-8"?>
<episodedetails>
  <title>NFO 第一集</title>
  <plot>单集 NFO 优先。</plot>
  <season>1</season>
  <episode>1</episode>
</episodedetails>
NFO
Scripts/build-app.sh >/dev/null
swift test >/dev/null
build/impacket-venv/bin/smbserver.py -port "$PORT" -username test -password test -smb2support \
  SHARE "$SHARE_DIR" >"$OUT/server.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..60}; do
  if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test "$APP" \
  --smb-server 127.0.0.1 --smb-port "$PORT" --smb-share SHARE --smb-user test --smb-pass test \
  --smb-name SMB --smb-scan --library-report "$OUT/library.json" \
  --capture-ui "$OUT/library.png" --ui-after 8 --quit-after 10 >"$OUT/app.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
for item in data["items"]:
    if item["title"] == "SMB 示例剧":
        print(item["episodes"][0]["id"]); break
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_SMB_PASSWORD=test "$APP" \
  --library-play "$EPISODE" --subtitle zh-Hans --seek 30 --freeze-at 31 --capture "$OUT/play.png" \
  --capture-after 12 --report "$OUT/play.json" --quit-after 14 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
library = json.load(open(os.path.join(out, "library.json")))
if library["rawWorks"] != 2 or library["rawEpisodes"] != 3:
    errors.append(f"counts {library['rawWorks']}/{library['rawEpisodes']}")
series = next((item for item in library["items"] if item["title"] == "SMB 示例剧"), None)
if series is None or len(series["episodes"]) != 2:
    errors.append("SMB show seasons not inherited")
elif not series.get("poster", "").startswith("file:"):
    errors.append(f"show poster {series.get('poster')}")
if library["items"][0]["sourceKind"] != "smb":
    errors.append("sourceKind not smb")
play = json.load(open(os.path.join(out, "play.json")))
if play.get("sourceKind") != "smb" or not 30.8 <= play.get("position", 0) <= 31.2:
    errors.append(f"play/seek {play.get('sourceKind')} {play.get('position')}")
if "S01E01.mkv" not in play.get("remotePath", ""):
    errors.append(f"remotePath {play.get('remotePath')}")
if not any("中文（简体）" in item.get("name", "") for item in play.get("subtitles", [])):
    errors.append("SMB external subtitle not loaded")
if not str(play.get("selectedSubtitle", "")).startswith("mpv:"):
    errors.append(f"subtitle not selected: {play.get('selectedSubtitle')}")
if library["items"][0]["title"] != "SMB NFO 电影":
    errors.append(f"NFO title {library['items'][0]['title']}")
if not str(library["items"][0].get("poster", "")).startswith("file:"):
    errors.append(f"poster {library['items'][0].get('poster')}")
if not os.path.isdir(os.path.join(out, "support", "SMBPosterCache")):
    errors.append("SMBPosterCache missing")
if not os.path.isdir(os.path.join(out, "support", "SMBSubtitleCache")):
    errors.append("SMBSubtitleCache missing")
for name in ["library.png", "play.png"]:
    if not os.path.exists(os.path.join(out, name)):
        errors.append(f"missing {name}")
cache = os.path.join(out, "support", "SMBCache")
if os.path.isdir(cache) and os.listdir(cache):
    errors.append("SMBCache should be empty for streaming playback")
if not play.get("file", "").startswith("http://127.0.0.1:"):
    errors.append(f"not loopback stream: {play.get('file')}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: SMB movie+2-season show NFO/poster/subtitle, seek 31s, no cache")
PY
