#!/bin/bash
# M3p: identical local files under different roots dedupe to one version.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/local-dedupe"
rm -rf "$OUT"; mkdir -p "$OUT/root-a/Movies" "$OUT/root-b/Movies" "$OUT/support"
cp Fixtures/generated/openfuse-fixture.mkv "$OUT/root-a/Movies/Dup Movie (2026).mkv"
cp Fixtures/generated/openfuse-fixture.mkv "$OUT/root-b/Movies/Dup Movie (2026).mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test "$APP" \
  --scan-local "$OUT/root-a" --library-report "$OUT/a.json" --quit-after 4 >"$OUT/a.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test "$APP" \
  --scan-local "$OUT/root-b" --library-report "$OUT/b.json" --quit-after 4 >"$OUT/b.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
data = json.load(open(os.path.join(out, "b.json")))
if data.get("rawWorks") != 2:
    errors.append(f"rawWorks {data.get('rawWorks')}")
if len(data.get("groups", [])) != 1:
    errors.append(f"groups {len(data.get('groups', []))}")
merged = data.get("merged", [])
if not merged or len(merged[0]["episodes"][0]["versions"]) != 1:
    errors.append(f"merged versions {merged}")
items = data.get("items", [])
versions = items[0]["episodes"][0]["versions"] if items else []
if not versions or not versions[0].get("contentKey"):
    errors.append(f"contentKey {versions}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: identical files across roots merge to one version (contentKey)")
PY
