#!/usr/bin/env bash
# Generates App/AnkiMac.xcodeproj and builds the app into out/app.
# Run scripts/build-backend.sh first.
#
#     scripts/build-app.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-Release}
(cd App && xcodegen generate --quiet)
xcodebuild -project App/AnkiMac.xcodeproj -scheme AnkiMac -configuration "$CONFIG" \
  -derivedDataPath out/DerivedData -quiet build
mkdir -p out/app
rm -rf out/app/AnkiMac.app
/bin/cp -cR "out/DerivedData/Build/Products/$CONFIG/AnkiMac.app" out/app/
echo "built: out/app/AnkiMac.app"
