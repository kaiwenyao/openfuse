#!/bin/bash
# Copy libmpv + non-system dependencies into OpenFuse.app/Contents/Frameworks,
# rewrite install names to @rpath and ad-hoc sign. Run after build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app"
# Rebuild so the executable still has absolute Homebrew dependencies; the
# bundling step rewrites them, so rerunning on an already-bundled app would
# have no roots to discover.
if [[ "${OPENFUSE_SKIP_BUILD:-0}" != "1" ]]; then
  Scripts/build-app.sh >/dev/null
fi
BIN="$APP/Contents/MacOS/OpenFuse"
FRAMEWORKS="$APP/Contents/Frameworks"
if [[ ! -x "$BIN" ]]; then
  echo "error: $BIN missing; run Scripts/build-app.sh first" >&2
  exit 1
fi
rm -rf "$FRAMEWORKS"
mkdir -p "$FRAMEWORKS"

python3 Tools/bundle_runtime.py "$BIN" "$FRAMEWORKS"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
# Verify no Homebrew paths remain in the executable or bundled dylibs.
if otool -L "$BIN" | grep -q '/opt/homebrew'; then
  echo "error: executable still links Homebrew libraries" >&2
  exit 1
fi
for lib in "$FRAMEWORKS"/*.dylib; do
  if otool -L "$lib" | grep -q '/opt/homebrew'; then
    echo "error: $(basename "$lib") still links Homebrew libraries" >&2
    exit 1
  fi
done
echo "self-contained runtime: $FRAMEWORKS"
