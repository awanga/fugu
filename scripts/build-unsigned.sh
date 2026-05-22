#!/usr/bin/env bash
#
# Build an unsigned local artifact for testing.
# Output: Fugu-<version>-unsigned.zip and matching .sha256 in the project root.
#
# Uses the Development configuration (no hardened runtime) so the unsigned
# app can be opened directly on a developer machine without Gatekeeper blocking
# it due to a missing code signature on a hardened-runtime binary.
#
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(defaults read "$(pwd)/Info.plist" CFBundleShortVersionString)
ARTIFACT="Fugu-${VERSION}-unsigned.zip"
BUILD_ROOT="$(pwd)/build"

echo "==> Building Fugu ${VERSION} (unsigned, Development config)"
xcodebuild \
    -project Fugu.xcodeproj \
    -scheme Fugu \
    -configuration Development \
    -destination 'platform=macOS' \
    SYMROOT="$BUILD_ROOT" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

APP=$(find "$BUILD_ROOT" -name "Fugu.app" -maxdepth 4 | head -1)
if [ -z "$APP" ]; then
    echo "ERROR: Fugu.app not found after build" >&2
    exit 1
fi

echo "==> Packaging ${APP}"
rm -f "$ARTIFACT" "${ARTIFACT}.sha256"
ditto -c -k --keepParent "$APP" "$ARTIFACT"
shasum -a 256 "$ARTIFACT" > "${ARTIFACT}.sha256"

echo "==> Done"
echo "    Artifact : $ARTIFACT"
echo "    SHA-256  : $(cat "${ARTIFACT}.sha256")"
