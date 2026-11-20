#!/bin/bash
# Simulated two-device resume: A plays -> shared sync -> B resumes.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/progress-sync"
SYNC="$OUT/shared-progress.json"
A="$OUT/device-a"
B="$OUT/device-b"
rm -rf "$OUT"; mkdir -p "$A" "$B"
python3 Tools/make_library_fixture.py >/dev/null

OPENFUSE_SUPPORT_DIR="$A" "$APP" --scan-local "$PWD/build/library-fixture" \
  --library-report "$OUT/a-library.json" --quit-after 2 >"$OUT/a.log" 2>&1 || true
sleep 0.5
EPISODE=$(python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(f"{sys.argv[1]}/a-library.json"))
for item in data["items"]:
    if item["sourceKind"] == "local" and item["title"] == "示例剧":
        print(item["episodes"][0]["id"]); break
PY
)
OPENFUSE_SUPPORT_DIR="$A" "$APP" --library-play "$EPISODE" --freeze-at 9.9 \
  --report "$OUT/a-play.json" --capture-after 12 --quit-after 14 >"$OUT/a.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$A" OPENFUSE_SYNC_FILE="$SYNC" "$APP" --sync-progress \
  --quit-after 2 >"$OUT/a-sync.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$B" "$APP" --scan-local "$PWD/build/library-fixture" \
  --library-report "$OUT/b-library.json" --quit-after 2 >"$OUT/b.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$B" OPENFUSE_SYNC_FILE="$SYNC" "$APP" --sync-progress \
  --quit-after 2 >"$OUT/b-sync.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$B" "$APP" --library-play "$EPISODE" \
  --report "$OUT/b-play.json" --capture-after 5 --quit-after 8 >"$OUT/b.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
a = json.load(open(os.path.join(out, "a-play.json")))
b = json.load(open(os.path.join(out, "b-play.json")))
if not 9.8 <= a.get("position", 0) <= 10.1:
    errors.append(f"A position {a.get('position')}")
if not 12.0 <= b.get("position", 0) <= 18.5:
    errors.append(f"B did not resume (position {b.get('position')})")
if b.get("sourceKind") != "local":
    errors.append(f"B sourceKind {b.get('sourceKind')}")
print("A", a.get("position"), "B", b.get("position"))
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: A progress synced to B; B resumed instead of starting at 0")
PY
