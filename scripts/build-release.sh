#!/usr/bin/env bash
#
# Build a signed, notarized, stapled .dmg release artifact.
#
# Required environment variables:
#   APPLE_TEAM_ID               — 10-character Apple Developer Team ID
#   APPLE_NOTARYTOOL_KEY_ID     — App Store Connect API key ID
#   APPLE_NOTARYTOOL_ISSUER     — App Store Connect API issuer UUID
#   APPLE_NOTARYTOOL_KEY_PATH   — path to the .p8 private key file
#
# The signing identity ("Developer ID Application: ... (TEAM_ID)") must
# already be present in the keychain before running this script.
#
# Output: Fugu-<version>.dmg and Fugu-<version>.dmg.sha256 in the project root.
#
set -euo pipefail

cd "$(dirname "$0")/.."

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_NOTARYTOOL_KEY_ID:?APPLE_NOTARYTOOL_KEY_ID is required}"
: "${APPLE_NOTARYTOOL_ISSUER:?APPLE_NOTARYTOOL_ISSUER is required}"
: "${APPLE_NOTARYTOOL_KEY_PATH:?APPLE_NOTARYTOOL_KEY_PATH is required}"

VERSION=$(defaults read "$(pwd)/Info.plist" CFBundleShortVersionString)
DMG="Fugu-${VERSION}.dmg"

echo "==> Building Fugu ${VERSION} (signed, Deployment config)"
xcodebuild \
    -project Fugu.xcodeproj \
    -scheme Fugu \
    -configuration Deployment \
    -destination 'platform=macOS' \
    DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
    clean build

APP=$(find build -name "Fugu.app" -maxdepth 4 | head -1)
if [ -z "$APP" ]; then
    echo "ERROR: Fugu.app not found after build" >&2
    exit 1
fi

echo "==> Verifying code signature"
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'TeamIdentifier|Authority'

echo "==> Creating ${DMG}"
rm -f "$DMG" "${DMG}.sha256"
hdiutil create \
    -volname "Fugu" \
    -srcfolder "$APP" \
    -ov \
    -format UDZO \
    "$DMG"

echo "==> Signing disk image"
codesign --force --sign "Developer ID Application" \
    --options runtime \
    --timestamp \
    "$DMG"

echo "==> Notarizing (this may take a few minutes)"
xcrun notarytool submit "$DMG" \
    --key "${APPLE_NOTARYTOOL_KEY_PATH}" \
    --key-id "${APPLE_NOTARYTOOL_KEY_ID}" \
    --issuer "${APPLE_NOTARYTOOL_ISSUER}" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG"

echo "==> Generating checksum"
shasum -a 256 "$DMG" > "${DMG}.sha256"

echo "==> Done"
echo "    Artifact : $DMG"
echo "    SHA-256  : $(cat "${DMG}.sha256")"
