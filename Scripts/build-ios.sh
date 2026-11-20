#!/bin/bash
# Build the iPhone/iPad app.
#
#   Scripts/build-ios.sh                          # iOS Simulator, unsigned
#   Scripts/build-ios.sh --device --team TEAMID   # iphoneos, automatic signing
#   Scripts/build-ios.sh 'platform=iOS Simulator,id=UDID' build/out Debug
#
# Simulator builds stay unsigned (CODE_SIGNING_ALLOWED=NO). Device builds use
# Xcode automatic signing with the Apple Development identity of TEAMID, which
# is what a free personal team provides. Use Scripts/install-openfuse-ios.sh to
# build, install over USB and read the provisioning-profile expiry.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
xcodegen generate --spec project.yml >/dev/null

MODE="simulator"
TEAM="${OPENFUSE_DEVELOPMENT_TEAM:-}"
DEST=""
DERIVED="build/mobile-derived"
CONFIG="Debug"
POS_DEST=""
POS_DERIVED=""
BUNDLE_ID="${OPENFUSE_BUNDLE_ID:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --device) MODE="device"; shift ;;
    --simulator) MODE="simulator"; shift ;;
    --team) TEAM="${2:-}"; shift 2 ;;
    --derived) DERIVED="${2:-}"; shift 2 ;;
    --configuration) CONFIG="${2:-}"; shift 2 ;;
    --bundle-id) BUNDLE_ID="${2:-}"; shift 2 ;;
    --help|-h)
      sed -n '2,12p' "$0"; exit 0 ;;
    *)
      if [ -z "$POS_DEST" ]; then POS_DEST="$1"; DEST="$1"; elif [ -z "$POS_DERIVED" ]; then POS_DERIVED="$1"; DERIVED="$1"; else CONFIG="$1"; fi
      shift ;;
  esac
done

if [ "$MODE" = "device" ]; then
  [ -n "$DEST" ] || DEST="generic/platform=iOS"
elif [ -z "$DEST" ]; then
  DEST="generic/platform=iOS Simulator"
fi

EXTRA=()
if [[ "$DEST" == *"Simulator"* ]]; then
  EXTRA+=(CODE_SIGNING_ALLOWED=NO)
elif [ -n "$TEAM" ]; then
  EXTRA+=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
else
  echo "warning: building for a device without a team; the app will be unsigned and cannot be installed." >&2
  EXTRA+=(CODE_SIGNING_ALLOWED=NO)
fi
if [ -n "$BUNDLE_ID" ]; then
  EXTRA+=(PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID")
fi

xcodebuild \
  -project OpenFuseMobile.xcodeproj \
  -scheme OpenFuseMobile \
  -configuration "$CONFIG" \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  "${EXTRA[@]}" \
  build

PRODUCT="$DERIVED/Build/Products/${CONFIG}-iphonesimulator/OpenFuse.app"
if [[ "$DEST" == *"platform=iOS"* && "$DEST" != *"Simulator"* ]]; then
  PRODUCT="$DERIVED/Build/Products/${CONFIG}-iphoneos/OpenFuse.app"
fi
echo "built: $PRODUCT"
