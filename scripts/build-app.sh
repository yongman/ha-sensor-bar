#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Expected a numeric major.minor.patch version and numeric BUILD_NUMBER." >&2
    exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=14.0
swift build -c release --arch arm64 -Xswiftc -warnings-as-errors
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP="dist/HA Sensor Bar.app"
rm -rf "$APP" dist/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HASensorBarApp" "$APP/Contents/MacOS/HASensorBarApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
swift scripts/generate-icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf dist/AppIcon.iconset
plutil -lint "$APP/Contents/Info.plist"
test "$(lipo -archs "$APP/Contents/MacOS/HASensorBarApp")" = "arm64"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP ($VERSION, arm64)"
