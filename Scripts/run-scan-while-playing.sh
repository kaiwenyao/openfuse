#!/bin/bash
# M3 T07: rescan while playback continues; corrupt single file does not abort.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/scan-while-playing"
rm -rf "$OUT"; mkdir -p "$OUT/support" "$OUT/support-corrupt" "$OUT/corrupt"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/make_library_fixture.py >/dev/null
# A corrupt sibling must not abort the scan.
cp -R build/library-fixture/* "$OUT/corrupt/"
printf 'not a video' > "$OUT/corrupt/Movies/Broken.Movie.2026.mkv"
OPENFUSE_SUPPORT_DIR="$OUT/support-corrupt" "$APP" --scan-local "$OUT/corrupt" \
  --library-report "$OUT/corrupt-report.json" --quit-after 3 >"$OUT/corrupt.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --scan-local build/library-fixture \
  --library-report "$OUT/library.json" --quit-after 3 >"$OUT/scan.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/library.json"))
for item in data["items"]:
    if item["title"] == "示例剧":
        print(item["episodes"][0]["id"]); break
PY
)
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --library-play "$EPISODE" \
  --rescan-local build/library-fixture --freeze-at 12 \
  --capture "$OUT/playing.png" --capture-after 15 \
  --report "$OUT/playing.json" --quit-after 17 >"$OUT/play.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
corrupt = json.load(open(os.path.join(out, "corrupt-report.json")))
if any("Broken" in item.get("title", "") for item in corrupt.get("items", [])):
    errors.append("corrupt file was not filtered")
if corrupt["works"] < 1:
    errors.append(f"corrupt scan produced no works: {corrupt['works']}")
play = json.load(open(os.path.join(out, "playing.json")))
if play.get("position", 0) < 11.8:
    errors.append(f"playback not at 12s after rescan: {play.get('position')}")
status = play.get("libraryStatus", "")
if "扫描" not in status:
    errors.append(f"rescan status missing: {status!r}")
if not os.path.exists(os.path.join(out, "playing.png")):
    errors.append("missing playing.png")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: rescan while playing (position 12s) and corrupt-file scan survived")
PY
