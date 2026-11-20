#!/bin/bash
# Build iOS/iPadOS, tvOS and visionOS targets (generic destinations, no signing).
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then brew install xcodegen; fi
xcodegen generate --spec project.yml >/dev/null

build() {
  local scheme="$1" destination="$2" derived="$3"
  xcodebuild -project OpenFuseMobile.xcodeproj -scheme "$scheme" -configuration Debug \
    -destination "$destination" -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build \
    | tail -1
}

build OpenFuseMobile 'generic/platform=iOS Simulator' build/mobile-derived
build OpenFuseTV 'generic/platform=tvOS Simulator' build/tv-derived
build OpenFuseVision 'generic/platform=visionOS Simulator' build/vision-derived
echo "built: iOS/iPadOS, tvOS, visionOS (generic simulator)"
