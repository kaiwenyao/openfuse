#!/bin/bash
# T07 basic: 10,000-file scan, cancellation, and preservation of the old library.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
ROOT="$PWD/build/stress-library"
OUT="$PWD/build/scan-stress"
COUNT=10000

if [[ ! -d "$ROOT" ]]; then
  python3 - "$ROOT" "$COUNT" <<'PY'
import os, sys
root, count = sys.argv[1], int(sys.argv[2])
for i in range(count):
    d = os.path.join(root, "Movies", f"Movie {i:05d} (2020)")
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, f"Movie {i:05d} (2020).mkv"), "wb").close()
PY
fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT"

measure() {
  python3 - "$@" <<'PY'
import subprocess, sys, time
start = time.time()
subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(f"{time.time() - start:.2f}")
PY
}

FULL=$(measure env OPENFUSE_SUPPORT_DIR="$OUT/support-full" "$APP" \
  --scan-local "$ROOT" --library-report "$OUT/full.json" --quit-after 2)

env OPENFUSE_SUPPORT_DIR="$OUT/support-cancel" "$APP" --scan-local "$ROOT" \
  --cancel-scan-after 0.05 --library-report "$OUT/cancelled.json" --quit-after 2 \
  >"$OUT/app.log" 2>&1 || true

env OPENFUSE_SUPPORT_DIR="$OUT/support-full" "$APP" --scan-local "$ROOT" \
  --cancel-scan-after 0.05 --library-report "$OUT/preserved.json" --quit-after 2 \
  >"$OUT/app.log" 2>&1 || true

python3 - "$OUT" "$COUNT" "$FULL" <<'PY'
import json, os, sys
out, count, elapsed = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
def load(name):
    return json.load(open(os.path.join(out, name), encoding="utf-8"))
errors = []
full = load("full.json")
if full.get("rawWorks") != count or full.get("rawEpisodes") != count:
    errors.append(f"full: {full.get('rawWorks')}/{full.get('rawEpisodes')}")
if count != 10000:
    errors.append("stress count mismatch")
cancelled = load("cancelled.json")
if cancelled.get("rawWorks") != 0 or "取消" not in cancelled.get("status", ""):
    errors.append(f"cancelled: {cancelled.get('rawWorks')} {cancelled.get('status')}")
preserved = load("preserved.json")
if preserved.get("rawWorks") != count or "取消" not in preserved.get("status", ""):
    errors.append(f"preserved: {preserved.get('rawWorks')} {preserved.get('status')}")
summary = {
    "count": count,
    "fullSeconds": elapsed,
    "fullWorks": full.get("rawWorks"),
    "fullEpisodes": full.get("rawEpisodes"),
    "cancelWorks": cancelled.get("rawWorks"),
    "cancelStatus": cancelled.get("status"),
    "preservedWorks": preserved.get("rawWorks"),
    "preservedStatus": preserved.get("status"),
}
json.dump(summary, open(os.path.join(out, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: {count} works/episodes scanned in {elapsed:.2f}s; cancel leaves 0; cancelled rescan preserves {count}")
print(f"reports: {out}")
PY
