#!/bin/bash
# M3d manual metadata override acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/editing-acceptance"
SUPPORT="$OUT/support"
if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
python3 Tools/make_library_fixture.py >/dev/null
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT"; mkdir -p "$SUPPORT"

OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --scan-local "$PWD/build/library-fixture" \
  --library-report "$OUT/base.json" --quit-after 3 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-work "示例剧" \
  --library-edit-title "示例剧（人工纠错）" --library-edit-year 2024 \
  --library-edit-overview "人工填写的剧情简介" \
  --library-edit-poster "https://example.com/poster.jpg" \
  --library-report "$OUT/applied.json" --capture-ui "$OUT/edited.png" \
  --ui-after 3 --quit-after 4 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-report "$OUT/persisted.json" \
  --quit-after 2 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-work "示例剧" --library-clear-override \
  --library-report "$OUT/cleared.json" --quit-after 2 >"$OUT/app.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
def load(name):
    return json.load(open(os.path.join(out, name), encoding="utf-8"))

def find(report):
    return [item for item in report["items"] if item["title"].startswith("示例剧")][0]

errors = []
base = find(load("base.json"))
if base["overridden"] is not False:
    errors.append("base: unexpectedly overridden")
applied = find(load("applied.json"))
if applied["title"] != "示例剧（人工纠错）" or applied["year"] != 2024:
    errors.append(f"applied: {applied['title']} {applied['year']}")
if not applied["poster"].startswith("remote:") or not applied["overridden"]:
    errors.append(f"applied: poster/flag {applied['poster']} {applied['overridden']}")
if "人工填写的剧情简介" not in applied["overview"]:
    errors.append("applied: overview missing")
persisted = find(load("persisted.json"))
if persisted["title"] != "示例剧（人工纠错）" or not persisted["overridden"]:
    errors.append("persisted: override lost")
cleared = find(load("cleared.json"))
if cleared["title"] != "示例剧" or cleared["overridden"]:
    errors.append(f"cleared: {cleared['title']} {cleared['overridden']}")
if not os.path.exists(os.path.join(out, "edited.png")):
    errors.append("missing capture")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: manual title/year/overview/poster override, persistence, clear")
print(f"captures: {out}")
PY
