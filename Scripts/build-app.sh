#!/bin/bash
# Build a runnable .app bundle for local development.
#
#   Scripts/build-app.sh            release build into build/OpenFuse.app
#   open build/OpenFuse.app
#
# M1 links Homebrew's libmpv at runtime (brew install mpv). Bundling libmpv and
# its codec stack into the app is part of the M5 packaging work; the build
# script fails loudly if the library is missing instead of producing a broken
# bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
if [[ ! -d /opt/homebrew/opt/mpv ]]; then
  echo "error: libmpv not found. Run: brew install mpv" >&2
  exit 1
fi

swift build -c "$CONFIG"

APP="build/OpenFuse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/OpenFuse" "$APP/Contents/MacOS/OpenFuse"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
cp Scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :OpenFuseCommit string $COMMIT" "$APP/Contents/Info.plist" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Set :OpenFuseCommit $COMMIT" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :OpenFuseBuildDate string $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true

# A stable ad-hoc signature keeps macOS from invalidating the bundle after
# each rebuild during local testing.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "built $APP"
echo "launch: open $APP"
echo "cli   : $APP/Contents/MacOS/OpenFuse --open <file> --capture /tmp/frame.png --capture-after 3"
