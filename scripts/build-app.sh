#!/usr/bin/env bash
# Generates App/AnkiMac.xcodeproj and builds the app into out/app.
# Run scripts/build-backend.sh first.
#
#     scripts/build-app.sh [Debug|Release]
#
# ANKIMAC_VERSION overrides the version (project.yml's MARKETING_VERSION);
# SPARKLE_PUBLIC_ED_KEY turns on in-app updates. The release workflow sets both
# (docs/RELEASING.md).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-Release}
# Ad-hoc signatures change with every build, and the keychain only trusts the
# exact binary that was allowed, so the saved AnkiWeb login prompts again after
# each rebuild. A local "AnkiMac Development" certificate keeps the signature
# stable; without one, builds stay ad-hoc.
IDENTITY="AnkiMac Development"
# The build number is the commit count: Sparkle compares it, and it only goes
# up along master.
SETTINGS=("CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)")
if [ -n "${ANKIMAC_VERSION:-}" ]; then
  SETTINGS+=("MARKETING_VERSION=$ANKIMAC_VERSION")
fi
# Without the key the app never starts its updater (SoftwareUpdate.isConfigured).
if [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
  SETTINGS+=("SPARKLE_PUBLIC_ED_KEY=$SPARKLE_PUBLIC_ED_KEY")
fi
(cd App && xcodegen generate --quiet)
xcodebuild -project App/AnkiMac.xcodeproj -scheme AnkiMac -configuration "$CONFIG" \
  -derivedDataPath out/DerivedData -quiet build "${SETTINGS[@]}"
mkdir -p out/app
rm -rf out/app/AnkiMac.app
/bin/cp -cR "out/DerivedData/Build/Products/$CONFIG/AnkiMac.app" out/app/
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --timestamp=none -s "$IDENTITY" out/app/AnkiMac.app
fi
echo "built: out/app/AnkiMac.app"
