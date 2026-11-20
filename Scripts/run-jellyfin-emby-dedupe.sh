#!/bin/bash
# M5g: Jellyfin + Emby same fixture aggregate into one group per title.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/jellyfin-emby-dedupe"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
python3 Tools/jellyfin_fixture.py --port 8096 --mobile-sample --log "$OUT/jf.log" >"$OUT/jf.out" 2>&1 &
JFPID=$!
python3 Tools/jellyfin_fixture.py --port 8097 --mobile-sample --log "$OUT/emby.log" >"$OUT/emby.out" 2>&1 &
EMBYPID=$!
trap 'kill "$JFPID" "$EMBYPID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 http://127.0.0.1:8096/System/Info/Public >/dev/null 2>&1 \
     && curl -sS --max-time 1 http://127.0.0.1:8097/System/Info/Public >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --jellyfin-url http://127.0.0.1:8096 \
  --jellyfin-user test --jellyfin-pass test --jellyfin-name Jellyfin --jellyfin-scan \
  --library-report "$OUT/jellyfin.json" --quit-after 8 >"$OUT/jf-app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" "$APP" --emby-url http://127.0.0.1:8097 \
  --emby-user test --emby-pass test --emby-name Emby --emby-scan \
  --library-report "$OUT/both.json" --capture-ui "$OUT/library.png" --ui-after 5 \
  --quit-after 8 >"$OUT/emby-app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
data = json.load(open(os.path.join(out, "both.json")))
errors = []
if data["rawWorks"] != 4 or data["rawEpisodes"] != 6:
    errors.append(f"raw {data['rawWorks']}/{data['rawEpisodes']} (expected 4/6)")
if len(data["groups"]) != 2:
    errors.append(f"groups {len(data['groups'])} (expected 2 after dedupe)")
for group in data["groups"]:
    if set(group.get("sources", [])) != {"jellyfin", "emby"}:
        errors.append(f"group sources {group.get('sources')}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Jellyfin+Emby raw 4 works/6 episodes dedupe to 2 groups with both sources")
PY
