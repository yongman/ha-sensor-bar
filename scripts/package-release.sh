#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a numeric major.minor.patch version." >&2
    exit 1
fi
APP="dist/HA Sensor Bar.app"
test -d "$APP"
ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
test "$ACTUAL_VERSION" = "$VERSION"
codesign --verify --deep --strict "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/HASensorBarApp")" = "arm64"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ha-sensor-bar-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/HA Sensor Bar.app"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.md "$STAGE/Installation.txt"
DMG="HA-Sensor-Bar-$VERSION-arm64.dmg"
ZIP="HA-Sensor-Bar-$VERSION-arm64.zip"
rm -f "dist/$DMG" "dist/$ZIP"
hdiutil create -volname "HA Sensor Bar" -srcfolder "$STAGE" -ov -format UDZO "dist/$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ZIP"
(
    cd dist
    shasum -a 256 "$DMG" "$ZIP" > SHA256SUMS.txt
    cp SHA256SUMS.txt "HA-Sensor-Bar-$VERSION-arm64.sha256"
    shasum -a 256 -c SHA256SUMS.txt
)
echo "Packaged dist/$DMG and dist/$ZIP"
