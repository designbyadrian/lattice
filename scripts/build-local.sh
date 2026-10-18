#!/usr/bin/env bash
# Local Release build with a stable code-signing identity so Accessibility /
# Screen Recording grants persist across rebuilds (ADDENDUM-2 D10).
#
# Prefer an "Apple Development" certificate from a free Apple ID, or a
# self-signed certificate created once in Keychain Access. Set
# LATTICE_CODE_SIGN_IDENTITY to that identity's exact name.
#
# Recovery if grants are stuck:
#   tccutil reset Accessibility com.designbyadrian.lattice
#   tccutil reset ScreenCapture com.designbyadrian.lattice
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY="${LATTICE_CODE_SIGN_IDENTITY:-Apple Development}"
CONFIGURATION="${LATTICE_CONFIGURATION:-Release}"
DERIVED="${LATTICE_DERIVED_DATA:-$ROOT/.build/DerivedData}"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

xcodebuild \
  -project Lattice.xcodeproj \
  -scheme Lattice \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="${LATTICE_DEVELOPMENT_TEAM:-}" \
  build

APP="$DERIVED/Build/Products/$CONFIGURATION/Lattice.app"
BIN="$APP/Contents/MacOS/Lattice"

if [[ "$CONFIGURATION" == "Release" ]]; then
  ./scripts/check-release-strings.sh "$BIN"
fi

echo "Built: $APP"
echo "Signed with: $IDENTITY"
echo "Bundle id: com.designbyadrian.lattice"
