#!/bin/bash
# Build the iPhone/iPad app. Requires Xcode; XcodeGen is installed on demand.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
xcodegen generate --spec project.yml >/dev/null
DESTINATION="${1:-generic/platform=iOS Simulator}"
DERIVED="${2:-build/mobile-derived}"
CONFIG="${3:-Debug}"
xcodebuild \
  -project OpenFuseMobile.xcodeproj \
  -scheme OpenFuseMobile \
  -configuration "$CONFIG" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build
PRODUCT="$DERIVED/Build/Products/${CONFIG}-iphonesimulator/OpenFuse.app"
if [[ "$DESTINATION" == *"platform=iOS"* && "$DESTINATION" != *"Simulator"* ]]; then
  PRODUCT="$DERIVED/Build/Products/${CONFIG}-iphoneos/OpenFuse.app"
fi
echo "built: $PRODUCT"
