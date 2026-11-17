#!/usr/bin/env bash
# Packs out/app/AnkiMac.app into a drag-to-Applications disk image.
#
#     scripts/package-dmg.sh [version]
#
# Writes out/AnkiMac-<version>.dmg and a .sha256 beside it (the digest the
# Homebrew cask pins). Run scripts/build-app.sh first; this builds nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=out/app/AnkiMac.app
if [ ! -d "$APP" ]; then
  echo "error: $APP is missing; run scripts/build-app.sh first" >&2
  exit 1
fi
VERSION=${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}
DMG=out/AnkiMac-$VERSION.dmg

# A bundle whose signature doesn't hold is one macOS calls "damaged" on the
# user's machine, long after this could have said so.
codesign --verify --deep --strict "$APP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
# ditto keeps the extended attributes and the signature's seal as they are.
ditto "$APP" "$STAGE/AnkiMac.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "AnkiMac $VERSION" -srcfolder "$STAGE" \
  -fs APFS -format ULFO -ov "$DMG" >/dev/null
(cd out && shasum -a 256 "AnkiMac-$VERSION.dmg" > "AnkiMac-$VERSION.dmg.sha256")
echo "built: $DMG"
cat "$DMG.sha256"
