#!/bin/bash
# M5v: Trakt device code auto-poll until token (test skips Keychain).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/trakt-auto-auth"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
python3 Tools/trakt_fixture.py --port 8123 --log "$OUT/trakt.log" >"$OUT/server.out" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in {1..40}; do
  if curl -sS --max-time 1 http://127.0.0.1:8123/search/movie >/dev/null 2>&1; then break; fi
  sleep 0.25
done
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_TRAKT_SKIP_KEYCHAIN=1 "$APP" \
  --trakt-auto-auth --trakt-base http://127.0.0.1:8123 --trakt-client test-client \
  --trakt-secret test-secret --quit-after 8 >"$OUT/app.log" 2>&1 || true
sleep 0.5
python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
errors = []
log = open(os.path.join(out, "trakt.log"), encoding="utf-8").read()
for needle in ["/oauth/device/code", "/oauth/device/token"]:
    if needle not in log:
        errors.append(f"missing {needle}")
app = open(os.path.join(out, "app.log"), encoding="utf-8").read()
if "Trakt 授权成功" not in app:
    errors.append(f"app log: {app.strip()}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: Trakt device code auto-polled and token accepted")
PY
