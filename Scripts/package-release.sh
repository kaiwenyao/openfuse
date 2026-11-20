#!/bin/bash
# Build a self-contained OpenFuse.app and package a release ZIP named after the
# version and commit, with a SHA-256 sidecar and a copy of the installer.
#
#   Scripts/package-release.sh
#   -> build/OpenFuse-macOS-<version>-<sha>.zip
#   -> build/OpenFuse-macOS-<version>-<sha>.zip.sha256
#   -> build/install-openfuse-macos.sh
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh release >/dev/null
Scripts/bundle-runtime.sh >/dev/null

APP="build/OpenFuse.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
COMMIT=$(/usr/libexec/PlistBuddy -c 'Print :OpenFuseCommit' "$APP/Contents/Info.plist")
NAME="OpenFuse-macOS-${VERSION}-${COMMIT}"
ZIP="build/${NAME}.zip"

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
unzip -t "$ZIP" >/dev/null

(
  cd build
  shasum -a 256 "${NAME}.zip" | awk '{print $1}' > "${NAME}.zip.sha256"
)
cp Scripts/install-openfuse-macos.sh build/install-openfuse-macos.sh
chmod +x build/install-openfuse-macos.sh

echo "version: ${VERSION}"
echo "commit : ${COMMIT}"
echo "zip    : ${ZIP}"
echo "sha256 : $(cat "$ZIP.sha256")"
echo "script : build/install-openfuse-macos.sh"
