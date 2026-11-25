#!/bin/bash
# Build a self-contained OpenFuse.app and package the release assets in the same
# format as anypaste: one fixed-name zip for /releases/latest/download, one
# SHA-256 sidecar and a copy of the installer. The release tag carries the
# version and commit.
#
#   Scripts/package-release.sh
#   -> build/OpenFuse-macos.zip
#   -> build/OpenFuse-macos.zip.sha256
#   -> build/install-openfuse-macos.sh
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh release >/dev/null
Scripts/bundle-runtime.sh >/dev/null

APP="build/OpenFuse.app"
ZIP="build/OpenFuse-macos.zip"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
COMMIT=$(/usr/libexec/PlistBuddy -c 'Print :OpenFuseCommit' "$APP/Contents/Info.plist")

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
unzip -t "$ZIP" >/dev/null

(
  cd build
  # Keep the standard `shasum` two-space + filename format so the sidecar can
  # be consumed directly by `shasum -a 256 -c OpenFuse-macos.zip.sha256`.
  shasum -a 256 "OpenFuse-macos.zip" > "OpenFuse-macos.zip.sha256"
)
cp Scripts/install-openfuse-macos.sh build/install-openfuse-macos.sh
chmod +x build/install-openfuse-macos.sh
mkdir -p dist
cp Scripts/install-openfuse-macos.sh dist/install-openfuse-macos.sh
chmod +x dist/install-openfuse-macos.sh

echo "version: ${VERSION}"
echo "commit : ${COMMIT}"
echo "zip    : ${ZIP}"
echo "sha256 : $(cat "$ZIP.sha256")"
echo "script : build/install-openfuse-macos.sh"
