#!/bin/bash
# M3e manual merge/split acceptance on the local library.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/manual-merge"
SUPPORT="$OUT/support"
if [[ ! -f Fixtures/generated/openfuse-fixture.mkv ]]; then Scripts/make_fixtures.sh; fi
python3 Tools/make_library_fixture.py >/dev/null
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT"; mkdir -p "$SUPPORT"

OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --scan-local "$PWD/build/library-fixture" \
  --library-report "$OUT/base.json" --quit-after 2 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-work "示例剧" --library-merge "另一部剧" \
  --library-report "$OUT/merged.json" --capture-ui "$OUT/merged.png" \
  --ui-after 3 --quit-after 4 >"$OUT/app.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$SUPPORT" "$APP" --library-work "示例剧" --library-split \
  --library-report "$OUT/split.json" --quit-after 2 >"$OUT/app.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
def load(name):
    return json.load(open(os.path.join(out, name), encoding="utf-8"))
errors = []
base = load("base.json")
merged = load("merged.json")
split = load("split.json")
if len(base["groups"]) != 3:
    errors.append(f"base groups {len(base['groups'])}")
if len(merged["groups"]) != 2:
    errors.append(f"merged groups {len(merged['groups'])}")
# One group should contain both series works.
double = [g for g in merged["groups"] if len(g.get("workIDs", [])) == 2]
if len(double) != 1:
    errors.append(f"merged group workIDs {[g.get('workIDs') for g in merged['groups']]}")
if len(split["groups"]) != 3:
    errors.append(f"split groups {len(split['groups'])}")
if not os.path.exists(os.path.join(out, "merged.png")):
    errors.append("missing capture")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: manual merge (3→2 groups) and split (2→3 groups)")
print(f"captures: {out}")
PY
