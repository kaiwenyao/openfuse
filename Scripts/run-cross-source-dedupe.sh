#!/bin/bash
# M5ad: local + WebDAV content fingerprints dedupe to one version.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/cross-source-dedupe"
rm -rf "$OUT"; mkdir -p "$OUT/local/Movies" "$OUT/webdav/Movie" "$OUT/support"
cp Fixtures/generated/openfuse-hdr.mkv "$OUT/local/Movies/Remote Dup (2026).mkv"
cp Fixtures/generated/openfuse-hdr.mkv "$OUT/webdav/Movie/Remote Dup (2026).mkv"
mkdir -p "$OUT/smb/Movie"
cp Fixtures/generated/openfuse-hdr.mkv "$OUT/smb/Movie/Remote Dup (2026).mkv"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/webdav_fixture.py --root "$OUT/webdav" --port 8122 --log "$OUT/webdav.log" >"$OUT/webdav.out" 2>&1 &
WPID=$!
build/impacket-venv/bin/smbserver.py -port 1445 -username test -password test -smb2support SHARE "$OUT/smb" >"$OUT/smb.log" 2>&1 &
SPID=$!
trap 'kill "$WPID" "$SPID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 -u test:test http://127.0.0.1:8122/dav/ >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test "$APP" \
  --scan-local "$OUT/local" --library-report "$OUT/local.json" --quit-after 4 \
  >"$OUT/local.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test \
OPENFUSE_WEBDAV_USER=test OPENFUSE_WEBDAV_PASSWORD=test \
  "$APP" --webdav-url http://127.0.0.1:8122/dav/ --webdav-user test --webdav-pass test \
  --webdav-name WebDAV --webdav-scan --library-report "$OUT/web.json" --quit-after 6 \
  >"$OUT/web.log" 2>&1 || true
sleep 0.5
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_TOKEN=test OPENFUSE_SMB_PASSWORD=test "$APP" \
  --smb-server 127.0.0.1 --smb-port 1445 --smb-share SHARE --smb-user test --smb-pass test \
  --smb-name SMB --smb-scan --library-report "$OUT/smb.json" --quit-after 8 \
  >"$OUT/smb-app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
errors = []
data = json.load(open(os.path.join(out, "smb.json")))
if len(data.get("groups", [])) != 1:
    errors.append(f"groups {len(data.get('groups', []))}")
merged = data.get("merged", [])
if not merged or len(merged[0]["episodes"][0]["versions"]) != 1:
    errors.append(f"merged versions {merged}")
keys = {version.get("contentKey") for item in data.get("items", [])
        for episode in item.get("episodes", [])
        for version in episode.get("versions", [])}
if len(keys) != 1 or None in keys or "" in keys:
    errors.append(f"contentKeys {keys}")
sources = set()
for group in data.get("groups", []):
    sources.update(group.get("sources", []))
if not {"local", "webdav", "smb"}.issubset(sources):
    errors.append(f"sources {sources}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: local+WebDAV+SMB same content dedupes to one version")
PY
