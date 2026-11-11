#!/usr/bin/env bash
# Generates App/AnkiMac.xcodeproj and builds the app into out/app.
# Run scripts/build-backend.sh first.
#
#     scripts/build-app.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-Release}
# Ad-hoc signatures change with every build, and the keychain only trusts the
# exact binary that was allowed, so the saved AnkiWeb login prompts again after
# each rebuild. A local "AnkiMac Development" certificate keeps the signature
# stable; without one, builds stay ad-hoc.
IDENTITY="AnkiMac Development"
(cd App && xcodegen generate --quiet)
xcodebuild -project App/AnkiMac.xcodeproj -scheme AnkiMac -configuration "$CONFIG" \
  -derivedDataPath out/DerivedData -quiet build
mkdir -p out/app
rm -rf out/app/AnkiMac.app
/bin/cp -cR "out/DerivedData/Build/Products/$CONFIG/AnkiMac.app" out/app/
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --timestamp=none -s "$IDENTITY" out/app/AnkiMac.app
fi
echo "built: out/app/AnkiMac.app"
