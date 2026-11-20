#!/bin/bash
# Build a self-contained, ad-hoc signed OpenFuse.app and zip it.
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/bundle-runtime.sh
codesign --verify --deep --strict build/OpenFuse.app
ZIP="build/OpenFuse-macOS-self-contained.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/OpenFuse.app "$ZIP"
unzip -t "$ZIP" >/dev/null
echo "packaged $ZIP"
du -sh build/OpenFuse.app "$ZIP"
