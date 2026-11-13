#!/bin/bash
# Builds a universal Trace.app and packages it for download.
#
#   scripts/release.sh
#
# Output: dist/Trace-<version>.dmg and dist/Trace-<version>.zip
#
# Optional environment:
#   DEVELOPER_ID     "Developer ID Application: Name (TEAMID)". Without it the
#                    app is ad-hoc signed and macOS will warn on first launch.
#   NOTARY_PROFILE   A keychain profile created with
#                    `xcrun notarytool store-credentials`. With it (and
#                    DEVELOPER_ID) the DMG is notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
APP="build/Trace.app"
DMG="dist/Trace-$VERSION.dmg"
ZIP="dist/Trace-$VERSION.zip"

UNIVERSAL=1 CODESIGN_IDENTITY="${DEVELOPER_ID:--}" scripts/bundle.sh release
if [ -n "${DEVELOPER_ID:-}" ]; then
  # Notarization needs a secure timestamp, which the everyday build skips.
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi

rm -rf dist
mkdir -p dist/stage
cp -R "$APP" dist/stage/
ln -s /Applications dist/stage/Applications
hdiutil create -quiet -volname "Trace $VERSION" -srcfolder dist/stage -ov -format UDZO "$DMG"
rm -rf dist/stage
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
else
  echo "Not notarized: set DEVELOPER_ID and NOTARY_PROFILE to notarize."
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Version $VERSION"
lipo -archs "$APP/Contents/MacOS/Trace"
shasum -a 256 "$DMG" "$ZIP"
