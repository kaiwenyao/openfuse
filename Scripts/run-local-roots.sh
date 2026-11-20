#!/bin/bash
# M3o: persistent multi-root local libraries; scan all/remove.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/local-roots"
rm -rf "$OUT"; mkdir -p "$OUT/root-a/Movies" "$OUT/root-b/Movies" "$OUT/support"
cp Fixtures/generated/openfuse-fixture.mkv "$OUT/root-a/Movies/Alpha Movie (2026).mkv"
cp Fixtures/generated/openfuse-fixture.mkv "$OUT/root-b/Movies/Beta Movie (2026).mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test "$APP" \
  --scan-local "$OUT/root-a" --library-report "$OUT/a.json" --quit-after 4 \
  >"$OUT/a.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test "$APP" \
  --scan-local "$OUT/root-b" --library-report "$OUT/b.json" --quit-after 4 \
  >"$OUT/b.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test "$APP" \
  --remove-local-root "$OUT/root-b" --library-report "$OUT/removed.json" --quit-after 3 \
  >"$OUT/removed.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
both = json.load(open(os.path.join(out, "b.json")))
titles = [item["title"] for item in both.get("items", [])]
for title in ["Alpha Movie", "Beta Movie"]:
    if title not in titles:
        errors.append(f"missing {title} after two roots: {titles}")
if both.get("rawWorks") != 2:
    errors.append(f"works {both.get('rawWorks')}")
removed = json.load(open(os.path.join(out, "removed.json")))
titles = [item["title"] for item in removed.get("items", [])]
if "Beta Movie" in titles or "Alpha Movie" not in titles:
    errors.append(f"remove failed: {titles}")
roots = json.load(open(os.path.join(out, "support", "local-roots.json")))
if len(roots.get("roots", [])) != 1:
    errors.append(f"roots {roots}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: two local roots coexist; removing one keeps the other")
PY
