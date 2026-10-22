#!/bin/bash
# Builds a Release LiteDisplay.app (ad-hoc signed) and zips it into dist/.
# Usage: scripts/release.sh [version]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:$PATH"

VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)}"
# Build products must stay outside the (possibly cloud-synced) repository folder: see CLAUDE.md.
DERIVED="${TMPDIR:-/tmp}/LiteDisplay-release-DerivedData"

xcodegen generate >/dev/null
xcodebuild -project LiteDisplay.xcodeproj -scheme LiteDisplay -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CODE_SIGN_IDENTITY=- build

APP="$DERIVED/Build/Products/Release/LiteDisplay.app"
mkdir -p dist
ZIP="dist/LiteDisplay-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Built $ZIP"
echo "Note: the app is ad-hoc signed. First launch needs right-click › Open (or System Settings › Privacy & Security › Open Anyway)."
